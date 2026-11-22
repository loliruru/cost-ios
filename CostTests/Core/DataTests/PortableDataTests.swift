import Foundation
import GRDB
import Testing
@testable import Cost

private final class PortableFixtureMarker: NSObject {}

struct PortableDataTests {
    private typealias BackupSnapshot = [String: [[String: Data?]]]

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

        init(_ root: URL, database: AppDatabase? = nil,
             clearPrivateState: @escaping @Sendable () async throws -> Void = {}) throws {
            let database = try database ?? AppDatabase.inMemory()
            let visuals = ManagedVisualStore(database: database, root: root)
            let settings = try PortableSettingsStore(root: root, suiteName: UUID().uuidString)
            self.database = database
            self.visuals = visuals
            self.settings = settings
            transfer = LocalPortableDataRepository(database: database, visuals: visuals, settings: settings,
                maintenance: LedgerMaintenance(), root: root.appendingPathComponent("stage"), clearPrivateState: clearPrivateState)
        }
    }

    private actor PrivateResetFixture {
        private(set) var attempts = 0

        func clear() throws {
            attempts += 1
            if attempts == 1 { throw PortableDataError.storage }
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
        var corrupted = fixture.backup
        corrupted[corrupted.count - 1] ^= 1
        let damagedFile = root.appendingPathComponent("damaged.costbackup")
        try corrupted.write(to: damagedFile)
        await #expect(throws: PortableDataError.authenticationFailed) {
            try await ledger.transfer.prepare(damagedFile, kind: .backup, password: password)
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

        let encrypted = try await ledger.transfer.export(.backup, password: password)
        let second = try await ledger.transfer.export(.backup, password: password)
        let firstEnvelope = try Data(contentsOf: encrypted)
        let secondEnvelope = try Data(contentsOf: second)
        #expect(firstEnvelope.prefix(9) == Data("COSTBK01".utf8) + Data([1]))
        #expect(firstEnvelope[9..<37] != secondEnvelope[9..<37])
        let destination = try Ledger(root.appendingPathComponent("destination"))
        let roundTrip = try await destination.transfer.prepare(encrypted, kind: .backup, password: password)
        let restored = try await destination.transfer.confirm(roundTrip.token)
        #expect(restored.imported == 1 && !restored.settingsPending)
        #expect(try await destination.records.transaction(id: row.id) == row)
    }

    @Test func zipRejectsUnsafeNamesAndOversizedEntriesBeforeExtraction() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "settings.json"
        try Data("{}".utf8).write(to: root.appendingPathComponent(name))
        let archive = root.appendingPathComponent("test.zip")
        try PortableZIP.write(archive, root: root, names: [name])
        let original = try Data(contentsOf: archive)
        var unsafe = original
        let valid = Data(name.utf8)
        let invalid = Data("../escape.txt".utf8)
        let local = try #require(unsafe.range(of: valid))
        unsafe.replaceSubrange(local, with: invalid)
        let central = try #require(unsafe.range(of: valid))
        unsafe.replaceSubrange(central, with: invalid)
        try unsafe.write(to: archive)
        let output = root.appendingPathComponent("extracted")
        #expect(throws: PortableDataError.invalidFormat) { try PortableZIP.extract(archive, to: output) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.txt").path))
        var oversized = original
        // Single-entry writer's central entry begins immediately after its local header, name and data.
        let centralOffset = 30 + name.utf8.count + 2
        oversized.replaceSubrange((centralOffset + 24)..<(centralOffset + 28), with: [1, 32, 0, 0])
        try oversized.write(to: archive)
        #expect(throws: PortableDataError.tooLarge) { try PortableZIP.extract(archive, to: output) }
    }

    @Test func csvKeepsExactTextAndRejectsAConflictingBatch() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Ledger(root.appendingPathComponent("source"))
        let target = try Ledger(root.appendingPathComponent("target"))
        let note = "=SUM(1,2)\r\n\"账本\"\\N"
        let archived = try TestLedger.transaction(id: "archived", units: Int64.max, updated: 11, deleted: 11, note: note)
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

    @Test(.timeLimit(.minutes(1)))
    func largeBackupRestoresEveryTableAfterDeletionAndReplaysPendingSettings() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try await AppDatabase.open(at: root.appendingPathComponent("ledger.sqlite"))
        defer { try? database.writer.close() }
        let ledger = try Ledger(root, database: database)
        let cny = try CurrencyCode("CNY")
        let preferences = PortableSettings(base_currency_code: "CNY", theme_mode: "DARK",
            glass_quality: "MEDIUM", anomaly_sensitivity: "HIGH", dynamic_color_enabled: false,
            reduce_motion_enabled: true, anomaly_enabled: false)
        try await ledger.settings.replace(preferences)
        let png = root.appendingPathComponent("icon.png")
        try ManagedVisualTests().source().write(to: png)
        let image = try await ledger.visuals.importImage(file: png, kind: .icon, owner: "fixture")
        let imageBytes = try #require(try await ledger.visuals.imageData(id: image.id))
        var account = try #require(try await ledger.records.account(id: "seed-default-account"))
        account.visual = LedgerVisual(iconKey: "wallet", source: .image, iconAssetID: image.id)
        account.updatedAt = 100
        try await ledger.records.saveAccount(account)
        try await ledger.records.saveAccount(Account(id: "invest", name: "合成投资账户", createdAt: 10, updatedAt: 10))
        _ = try await ledger.records.saveOpening(AccountFundOpening(id: "opening-invest", accountID: "invest",
            kind: .investmentCost, enabled: true, currencyCode: cny, scale: 2,
            amountMinor: 200_000, startedAt: 1000, createdAt: 1000))
        let transfer = try await ledger.records.saveTransfer(
            AccountFundsRepositoryTests().transfer(profit: 10_000, withdrawal: true), expectedUpdatedAt: nil)
        let tag = try await ledger.records.saveTag(TestLedger.tag())
        let sampleAmount = try Money(minorUnits: 500, currencyCode: cny, scale: 2)
        let template = QuickTemplateContent(name: "合成模板", iconKey: "receipt", type: .expense,
            amount: sampleAmount, categoryID: "seed-expense-other", accountID: account.id, note: nil, tagIDs: [tag.id])
        _ = try await ledger.records.saveQuickTemplate(id: "sample-template", content: template, sortOrder: nil,
            expectedUpdatedAt: nil, at: 1000)
        let content = RecurringContent(name: "合成规则", type: .expense,
            amount: sampleAmount, categoryID: "seed-expense-other", accountID: account.id, note: nil, tagIDs: [tag.id],
            schedule: RecurringSchedule(startDay: 1, endDay: 1, minutes: 0, zoneID: "UTC"), catchUp: .createMissed)
        try await ledger.records.saveRecurringRule(id: "sample-rule", content: content, expectedVersion: nil, at: 1000)
        func process() async throws {
            let processor = ProcessRecurringRules(rules: ledger.records, currencies: ledger.records,
                provider: UnconfiguredRecurringFiatProvider(), environment: LedgerEnvironment(now: { 2 * 86_400_000 }))
            var blocked: Set<String> = []
            _ = try await processor.runDue(excluding: &blocked)
        }
        try await process()
        try await ledger.records.saveFiatQuote(FiatQuote(id: "fixture-fx", original: CurrencyCode("USD"), base: cny,
            rate: DecimalRate("7.123456789012345678"), providerID: "FIXTURE", dataTimestamp: 1000,
            rateEpochDay: nil, fetchedAt: 1001, expiresAt: 301000, kind: .latest))
        try await ledger.records.saveMarketQuote(MarketQuote(asset: CurrencyCode("BTC"), base: cny,
            providerID: "FIXTURE", price: DecimalRate("500000.123456789012345678"), venue: "fixture",
            dataTimestamp: 1000, fetchedAt: 1001, expiresAt: 301000))
        let analytics = GRDBAnalyticsRepository(database: ledger.database)
        try await analytics.saveAnomalyFeedback(AnomalyFeedback(id: "fixture-feedback", type: .markedNormal, kind: .category,
            categoryID: "seed-expense-other", currency: cny, amount: FrozenAmount(units: DecimalInteger("500"), scale: 2),
            version: AnomalyFeedback.featureVersion, createdAt: 1000))
        let archived = try TestLedger.transaction(id: "archived", units: .max, updated: 11, deleted: 11,
            tags: [tag.id], note: "=SUM(1,2)\r\n\"合成账本 Cafe\u{301}\"")
        _ = try await ledger.records.createTransaction(archived)
        let bulk = (0..<1_200).map { "bulk-\($0)" }
        try await ledger.database.writer.write { db in
            for id in bulk {
                try TransactionRecord(TestLedger.transaction(id: id, occurred: 20 * 86_400_000, note: "千笔性能验证")).insert(db)
            }
        }

        try await verifyLargeLedgerQueries(ledger, expectedIDs: bulk, currency: cny)
        let original = try await snapshot(ledger)
        let clock = ContinuousClock()
        let backupStarted = clock.now
        let backup = try await ledger.transfer.export(.backup, password: "")
        let exportDuration = backupStarted.duration(to: clock.now)
        #expect(exportDuration < .seconds(15))
        let existing = try TestLedger.transaction(id: "created-after-export")
        _ = try await ledger.records.createTransaction(existing)
        #expect(try await ledger.records.softDeleteTransaction(id: "bulk-0", at: 20))
        #expect(try await ledger.records.transaction(id: "bulk-0")?.deletedAt == 20)
        try await ledger.settings.setBaseCurrencyCode("USD")
        let changed = try await snapshot(ledger)
        let previewStarted = clock.now
        let preview = try await ledger.transfer.prepare(backup, kind: .backup, password: "")
        let previewDuration = previewStarted.duration(to: clock.now)
        #expect(previewDuration < .seconds(15))
        #expect(preview.transactions == 1_203 && preview.images == 1)

        try await ledger.database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fixture_failure BEFORE INSERT ON account_transfers
                BEGIN SELECT RAISE(ABORT, 'fixture restore failure'); END
                """)
        }
        await #expect(throws: (any Error).self) { try await ledger.transfer.confirm(preview.token) }
        let afterFailure = try await snapshot(ledger)
        expectSnapshot(afterFailure, equals: changed, after: "rollback")
        #expect(try await ledger.visuals.imageData(id: image.id) == imageBytes)
        let mediaFiles = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("visual_assets").path)
        #expect(mediaFiles == [URL(fileURLWithPath: image.relativePath).lastPathComponent])
        try await ledger.database.writer.write { try $0.execute(sql: "DROP TRIGGER fixture_failure") }
        let retry = try await ledger.transfer.prepare(backup, kind: .backup, password: "")

        let blocker = root.appendingPathComponent("portable-settings.json")
        try FileManager.default.removeItem(at: blocker)
        try PortableFiles.directory(blocker)
        try Data([1]).write(to: blocker.appendingPathComponent("blocker"))
        let restoreStarted = clock.now
        let outcome = try await ledger.transfer.confirm(retry.token)
        let restoreDuration = restoreStarted.duration(to: clock.now)
        #expect(restoreDuration < .seconds(15))
        #expect(outcome.settingsPending && outcome.imported == 1_203)
        #expect(try await ledger.records.transaction(id: existing.id) == nil)
        #expect(try await ledger.records.transaction(id: "bulk-0")?.deletedAt == nil)
        #expect(try await ledger.records.transaction(id: archived.id) == archived)
        let row = try await ledger.database.writer.read { try VisualAssetRecord.fetchOne($0, key: image.id) }
        #expect(row?.relative_path != image.relativePath)
        #expect(try await ledger.visuals.imageData(id: image.id) == imageBytes)
        #expect(try await ledger.database.writer.read { try RestoreStateRecord.fetchOne($0, key: 1) } != nil)
        try FileManager.default.removeItem(at: blocker)
        try await ledger.transfer.finishPendingMaintenance()
        #expect(try await ledger.database.writer.read { try RestoreStateRecord.fetchOne($0, key: 1) } == nil)
        let restoredPreferences = try PortableSettingsStore(root: root)
        let restoredSettings = try await restoredPreferences.snapshot().encoded()
        #expect(try restoredSettings == preferences.encoded())
        let restored = try await snapshot(ledger)
        expectSnapshot(restored, equals: original, after: "restore")
        #expect(try await ledger.records.transfer(id: transfer.id) == transfer)
        let profit = try #require(transfer.profitTransactionID)
        #expect(try await ledger.records.isManagedTransaction(id: profit))
        try await process()
        #expect(try await ledger.database.writer.read { try TransactionRecord.fetchCount($0) } == 1_203)
        #expect(try await ledger.database.writer.read { try RecurringExecutionRecord.fetchCount($0) } == 1)
    }

    @Test func resetRollsBackBeforeCommitAndResumesAfterReopeningWithoutSeedingCategoriesOrAccounts() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("ledger.sqlite")
        let database = try await AppDatabase.open(at: url)
        let localState = PrivateResetFixture()
        let ledger = try Ledger(root, database: database, clearPrivateState: { try await localState.clear() })
        let preferences = PortableSettings(base_currency_code: "USD", theme_mode: "DARK")
        try await ledger.settings.replace(preferences)
        let btc = try CurrencyCode("BTC")
        var enabledCrypto = try #require(try await ledger.records.currency(code: btc))
        enabledCrypto.isEnabled = true
        try await ledger.records.saveCurrency(enabledCrypto)
        let row = try TestLedger.transaction(id: "active")
        _ = try await ledger.records.createTransaction(row)
        _ = try await ledger.records.createTransaction(TestLedger.transaction(id: "deleted", updated: 20, deleted: 20))
        let png = root.appendingPathComponent("fixture.png")
        try ManagedVisualTests().source().write(to: png)
        let image = try await ledger.visuals.importImage(file: png, kind: .icon, owner: "fixture")
        var account = try #require(try await ledger.records.account(id: "seed-default-account"))
        account.visual = LedgerVisual(iconKey: "wallet", source: .image, iconAssetID: image.id)
        try await ledger.records.saveAccount(account)
        let exported = try await ledger.transfer.export(.csv, password: "")
        let preview = try await ledger.transfer.prepare(exported, kind: .csv, password: "")

        try await database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_reset BEFORE DELETE ON accounts
                BEGIN SELECT RAISE(ABORT, 'fixture reset failure'); END
                """)
        }
        await #expect(throws: (any Error).self) { try await ledger.transfer.resetLocalData() }
        #expect(await localState.attempts == 0)
        #expect(try await ledger.records.transaction(id: row.id) == row)
        #expect(try await ledger.visuals.imageData(id: image.id) != nil)
        #expect(FileManager.default.fileExists(atPath: exported.path))
        try await database.writer.write { try $0.execute(sql: "DROP TRIGGER fail_reset") }

        let outcome = try await ledger.transfer.resetLocalData()
        guard case .cleanupPending = outcome else {
            Issue.record("The fixture must interrupt private cleanup after commit")
            return
        }
        #expect(try await ledger.records.transaction(id: row.id) == nil)
        #expect(try await database.writer.read { try RestoreStateRecord.fetchOne($0, key: 1) } != nil)
        await #expect(throws: PortableDataError.expiredPreview) { try await ledger.transfer.confirm(preview.token) }
        try database.writer.close()

        let reopened = try await AppDatabase.open(at: url)
        defer { try? reopened.writer.close() }
        let afterRestart = try Ledger(root, database: reopened, clearPrivateState: { try await localState.clear() })
        try await afterRestart.transfer.finishPendingMaintenance()
        try await afterRestart.transfer.finishPendingMaintenance()
        #expect(await localState.attempts == 2)
        #expect(await afterRestart.settings.baseCurrencyCode() == "CNY")
        #expect(await afterRestart.settings.snapshot().theme_mode == nil)
        #expect(!FileManager.default.fileExists(atPath: exported.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(image.relativePath).path))
        #expect(FileManager.default.fileExists(atPath: png.path))
        #expect(try await afterRestart.records.currencies(includeDisabled: true).count == 15)
        #expect(try await afterRestart.records.currency(code: btc)?.isEnabled == false)
        try await reopened.writer.read { (db: Database) throws -> Void in
            for table in PortableLedger.tables where table != "currencies" {
                #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(PortableLedger.quote(table))") == 0)
            }
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try RestoreStateRecord.fetchOne(db, key: 1) == nil)
        }
        try await afterRestart.records.saveCategory(Category(id: "new-category", name: "新分类", type: .expense,
            createdAt: 30, updatedAt: 30))
        try await afterRestart.records.saveAccount(Account(id: "new-account", name: "新账户", createdAt: 30, updatedAt: 30))
        let newRow = try TestLedger.transaction(id: "new-entry", category: "new-category", account: "new-account",
            created: 31, updated: 31)
        #expect(try await afterRestart.records.createTransaction(newRow) == newRow)
    }

    private func verifyLargeLedgerQueries(_ ledger: Ledger, expectedIDs: [String], currency: CurrencyCode) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        var query = LedgerQuery()
        query.text = "千笔性能验证"
        var matched: [String] = []
        for _ in 0..<6 {
            let page = try await ledger.records.searchTransactions(query)
            #expect(page.rows.count == 200)
            matched.append(contentsOf: page.rows.map(\.id))
            query.cursor = page.next
        }
        #expect(query.cursor == nil)
        #expect(matched == expectedIDs.sorted(by: >))
        let range = try StatisticsRange(start: 20, endInclusive: 21)
        let analytics = GRDBAnalyticsRepository(database: ledger.database)
        var stream = analytics.observeStatistics(range: range, today: 21, currency: currency).makeAsyncIterator()
        let input = try #require(try await stream.next())
        let report = StatisticsReport(range: range, today: 21, currency: currency, input: input)
        #expect(report.total.expense.description == "1480800")
        let queryDuration = start.duration(to: clock.now)
        #expect(queryDuration < .seconds(15))
    }

    private func snapshot(_ ledger: Ledger) async throws -> BackupSnapshot {
        // Freeze the expected backup scope independently of the production copy plan.
        let tables = [
            "accounts", "account_fund_openings", "account_transfers", "anomaly_feedback", "categories",
            "crypto_price_quotes", "currencies", "fx_quotes", "quick_templates", "quick_template_tags",
            "recurring_executions", "recurring_rules", "recurring_rule_tags", "tags", "transactions",
            "transaction_tags", "visual_assets",
        ]
        return try await ledger.database.writer.read { db in
            var snapshot: BackupSnapshot = [:]
            for table in tables {
                let definitions = try db.columns(in: table)
                // Restore assigns a fresh media path. The image bytes and stored digest are compared independently.
                let columns = definitions.map(\.name).filter { table != "visual_assets" || $0 != "relative_path" }
                    .map(PortableLedger.quote).joined(separator: ",")
                let rows = try Row.fetchAll(db, sql: "SELECT \(columns) FROM \(PortableLedger.quote(table)) ORDER BY \(columns)")
                #expect(!rows.isEmpty, "Fixture has no rows in \(table)")
                snapshot[table] = try rows.map { row in
                    try PortableLedger.record(row).mapValues { $0.map { Data($0.utf8) } }
                }
            }
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            return snapshot
        }
    }

    private func expectSnapshot(_ actual: BackupSnapshot, equals expected: BackupSnapshot, after step: String) {
        for (table, rows) in expected {
            let matches = actual[table] == rows
            #expect(matches, "Rows in \(table) differ after \(step)")
        }
    }
}
