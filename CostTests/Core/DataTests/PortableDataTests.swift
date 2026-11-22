import Foundation
import GRDB
import Testing
@testable import Cost

private final class PortableFixtureMarker: NSObject {}

struct PortableDataTests {
    private struct Fixture: Decodable {
        let backup: Data
        let pbkdf2: String
    }

    private struct Ledger {
        let database: AppDatabase
        let visuals: ManagedVisualStore
        let settings: PortableSettingsStore
        let transfer: LocalPortableDataRepository
        var records: GRDBLedgerRepository { GRDBLedgerRepository(database: database) }

        init(_ root: URL) throws {
            let database = try AppDatabase.inMemory()
            let visuals = ManagedVisualStore(database: database, root: root)
            let settings = try PortableSettingsStore(root: root, suiteName: UUID().uuidString)
            self.database = database
            self.visuals = visuals
            self.settings = settings
            transfer = LocalPortableDataRepository(database: database, visuals: visuals, settings: settings,
                maintenance: LedgerMaintenance(), root: root.appendingPathComponent("stage"))
        }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portable-tests-\(UUID().uuidString)")
        try PortableFiles.directory(root)
        return root
    }

    @Test func javaEncryptedLegacyBackupAuthenticatesAndReplaysSchemaOne() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = try Ledger(root)
        let fixtureURL = try #require(Bundle(for: PortableFixtureMarker.self).url(forResource: "PortableBackupV1", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
        let password = "Cafe\u{301}-账本🔐-portable"
        let salt = Data((0..<16).map { UInt8($0) })
        let key = try BackupEnvelope.key(password, salt: salt)
        #expect(key.withUnsafeBytes { PortableFiles.hex($0) } == fixture.pbkdf2)
        let file = root.appendingPathComponent("android.costbackup")
        try fixture.backup.write(to: file)
        let existing = try TestLedger.transaction(id: "current")
        _ = try await ledger.records.createTransaction(existing)

        await #expect(throws: PortableDataError.authenticationFailed) {
            try await ledger.transfer.prepare(file, kind: .backup, password: "Café-账本🔐-portable")
        }
        #expect(try await ledger.records.transaction(id: "current") == existing)
        let preview = try await ledger.transfer.prepare(file, kind: .backup, password: password)
        #expect(preview.transactions == 1 && preview.images == 0)
        await ledger.transfer.discard(preview.token)
        await #expect(throws: PortableDataError.expiredPreview) { try await ledger.transfer.confirm(preview.token) }
        #expect(try await ledger.records.transaction(id: "current") == existing)

        let accepted = try await ledger.transfer.prepare(file, kind: .backup, password: password)
        let outcome = try await ledger.transfer.confirm(accepted.token)
        let row = try #require(try await ledger.records.transaction(id: "fixture-transaction"))
        let category = try #require(try await ledger.records.category(id: "fixture-category"))
        #expect(outcome.imported == 1 && !outcome.settingsPending)
        #expect(row.original.minorUnits == Int64.max && row.note == "=1+1, \"synthetic\"\r\n账本")
        #expect(row.crypto == nil && category.visual.source == .builtIn)
        #expect(try await ledger.records.transaction(id: "current") == nil)
        #expect(await ledger.settings.load().enabled == false)
    }

    @Test func csvKeepsExactTextAndRejectsAConflictingBatch() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Ledger(root.appendingPathComponent("source"))
        let target = try Ledger(root.appendingPathComponent("target"))
        let note = "=SUM(1,2)\r\n\"账本\"\\N"
        let archived = try TestLedger.transaction(id: "archived", units: Int64.max, deleted: 11, note: note)
        let row = try TestLedger.transaction(id: "same-id", requestKey: "unique", note: "new")
        _ = try await source.records.createTransaction(archived)
        _ = try await source.records.createTransaction(row)
        _ = try await target.records.createTransaction(TestLedger.transaction(id: "same-id", requestKey: "unique", note: "old"))
        let csv = try await source.transfer.export(.csv, password: "")
        let text = try String(contentsOf: csv, encoding: .utf8)
        #expect(text.contains("\"'9223372036854775807\""))
        #expect(text.contains("\"'=SUM(1,2)\r\n\"\"账本\"\"\\N\""))
        let preview = try await target.transfer.prepare(csv, kind: .csv, password: "")
        #expect(preview.transactions == 2)
        await #expect(throws: PortableDataError.conflictingRecords) { try await target.transfer.confirm(preview.token) }
        #expect(try await target.records.transaction(id: "archived") == nil)
        #expect(try await target.records.transaction(id: "same-id")?.note == "old")
        let clean = try Ledger(root.appendingPathComponent("clean"))
        let first = try await clean.transfer.prepare(csv, kind: .csv, password: "")
        let firstOutcome = try await clean.transfer.confirm(first.token)
        let again = try await clean.transfer.prepare(csv, kind: .csv, password: "")
        let repeated = try await clean.transfer.confirm(again.token)
        #expect(firstOutcome.imported == 2 && repeated.skipped == 2 && repeated.imported == 0)
        #expect(try await clean.records.transaction(id: "archived") == archived)
    }

    @Test func currentBackupPreservesManagedMediaAndLargeLedgerAndReplaysPendingSettings() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("source")
        let targetRoot = root.appendingPathComponent("target")
        try PortableFiles.directory(sourceRoot)
        try PortableFiles.directory(targetRoot)
        let source = try Ledger(sourceRoot)
        let target = try Ledger(targetRoot)
        try await source.settings.replace(PortableSettings(base_currency_code: "CNY", theme_mode: "DARK",
            glass_quality: "MEDIUM", anomaly_sensitivity: "HIGH", dynamic_color_enabled: false,
            reduce_motion_enabled: true, anomaly_enabled: false))
        let png = root.appendingPathComponent("icon.png")
        try ManagedVisualTests().source().write(to: png)
        let image = try await source.visuals.importImage(file: png, kind: .icon, owner: "fixture")
        var account = try #require(try await source.records.account(id: "seed-default-account"))
        account.visual = LedgerVisual(iconKey: "wallet", source: .image, iconAssetID: image.id)
        account.updatedAt = 100
        try await source.records.saveAccount(account)
        try await source.database.writer.write { db in
            for index in 0..<1_200 { try TransactionRecord(TestLedger.transaction(id: "bulk-\(index)")).insert(db) }
        }
        let backup = try await source.transfer.export(.backup, password: "")
        let preview = try await target.transfer.prepare(backup, kind: .backup, password: "")
        #expect(preview.transactions == 1_200 && preview.images == 1)

        let blocker = targetRoot.appendingPathComponent("portable-settings.json")
        try PortableFiles.directory(blocker)
        try Data([1]).write(to: blocker.appendingPathComponent("blocker"))
        let outcome = try await target.transfer.confirm(preview.token)
        #expect(outcome.settingsPending && outcome.imported == 1_200)
        let row = try await target.database.writer.read { try VisualAssetRecord.fetchOne($0, key: image.id) }
        #expect(row?.relative_path != image.relativePath)
        let sourceImage = try await source.visuals.imageData(id: image.id)
        let restoredImage = try await target.visuals.imageData(id: image.id)
        #expect(sourceImage != nil && sourceImage == restoredImage)
        #expect(try await target.database.writer.read { try RestoreStateRecord.fetchOne($0, key: 1) } != nil)
        try FileManager.default.removeItem(at: blocker)
        try await target.transfer.finishPendingSettings()
        #expect(try await target.database.writer.read { try RestoreStateRecord.fetchOne($0, key: 1) } == nil)
        let preferences = await target.settings.snapshot()
        #expect(preferences.theme_mode == "DARK" && preferences.glass_quality == "MEDIUM")
        #expect(preferences.dynamic_color_enabled == false && preferences.reduce_motion_enabled == true)
        #expect(preferences.anomaly_enabled == false && preferences.anomaly_sensitivity == "HIGH")
    }
}
