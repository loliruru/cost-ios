import Foundation
import GRDB

actor LocalPortableDataRepository: PortableDataRepository {
    private struct Stage: Sendable {
        let directory: URL
        let preview: PortableDataPreview
        let settings: PortableSettings?

        var databaseURL: URL { directory.appendingPathComponent("validated.sqlite") }
    }

    private let database: AppDatabase
    private let visuals: ManagedVisualStore
    private let settings: PortableSettingsStore
    private let maintenance: LedgerMaintenance
    private let root: URL
    private var pending: [UUID: Stage] = [:]
    private var exports: Set<URL> = []

    init(database: AppDatabase, visuals: ManagedVisualStore, settings: PortableSettingsStore,
         maintenance: LedgerMaintenance, root: URL) {
        self.database = database
        self.visuals = visuals
        self.settings = settings
        self.maintenance = maintenance
        self.root = root
    }

    func clearAbandonedStages() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for item in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where UUID(uuidString: item.lastPathComponent) != nil {
            try FileManager.default.removeItem(at: item)
        }
    }

    /// Call at startup, or while holding ledger maintenance.
    func finishPendingSettings() async throws {
        let pending = try await database.writer.read { db in try RestoreStateRecord.fetchOne(db, key: 1)?.settings }
        guard let pending else { return }
        try await settings.replace(PortableSettings.decode(Data(pending.utf8)))
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM restore_state WHERE id = 1 AND settings = ?", arguments: [pending])
        }
    }

    func export(_ kind: PortableDataKind, password: String) async throws -> URL {
        let directory = try newDirectory()
        let file = directory.appendingPathComponent(kind.fileName)
        do {
            if kind == .csv {
                let columns = try Self.csvColumns()
                try await database.writer.read { db in try PortableCSV.write(file, in: db, columns: columns) }
            } else {
                try await maintenance.withAccess {
                    try await self.finishPendingSettings()
                    try await self.visuals.withMaintenance {
                        try await self.writeBackup(file, directory: directory, password: password)
                    }
                }
            }
            // The Files exporter only needs the finalized document.
            for item in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where item != file {
                try FileManager.default.removeItem(at: item)
            }
            exports.insert(file)
            return file
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func writeBackup(_ file: URL, directory: URL, password: String) async throws {
        let snapshot = try PortableLedger.makeStaging(at: directory.appendingPathComponent("snapshot.sqlite"))
        let settings = await settings.snapshot()
        try await database.writer.read { source in
            try snapshot.write { target in
                for table in PortableLedger.tables { try PortableLedger.copy(table, from: source, to: target) }
            }
        }
        try PortableBackup.export(file, in: directory, snapshot: snapshot, mediaRoot: visuals.root,
            settings: settings, password: password)
    }

    func prepare(_ source: URL, kind: PortableDataKind, password: String) throws -> PortableDataPreview {
        let token = UUID()
        let directory = try newDirectory(id: token)
        do {
            let input = directory.appendingPathComponent("input")
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try Self.stageDocument(source, to: input, limit: kind == .csv ? PortableLimits.csv : PortableLimits.archive)
            let staged = try PortableLedger.makeStaging(at: directory.appendingPathComponent("validated.sqlite"))
            let preferences: PortableSettings?
            if kind == .csv {
                let columns = try Self.csvColumns()
                try staged.write { try PortableCSV.stage(input, into: $0, columns: columns) }
                preferences = nil
            } else {
                preferences = try PortableBackup.stage(input, in: directory, database: staged, password: password)
                try FileManager.default.removeItem(at: directory.appendingPathComponent("payload.zip"))
                try FileManager.default.removeItem(at: directory.appendingPathComponent("payload/database.sqlite"))
            }
            try FileManager.default.removeItem(at: input)
            let preview = try staged.read { db in
                try PortableDataPreview(token: token, kind: kind,
                    transactions: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions") ?? 0,
                    images: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM visual_assets") ?? 0)
            }
            pending[token] = Stage(directory: directory, preview: preview, settings: preferences)
            return preview
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func stageDocument(_ source: URL, to input: URL, limit: Int) throws {
        var coordinationError: NSError?
        var copyResult: Result<Void, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
            copyResult = Result { try PortableFiles.copy(url, to: input, limit: limit) }
        }
        if let coordinationError { throw coordinationError }
        guard let copyResult else { throw PortableDataError.storage }
        try copyResult.get()
    }

    func confirm(_ token: UUID) async throws -> PortableDataOutcome {
        guard let stage = pending.removeValue(forKey: token) else { throw PortableDataError.expiredPreview }
        defer { try? FileManager.default.removeItem(at: stage.directory) }
        let source = try DatabaseQueue(path: stage.databaseURL.path, configuration: AppDatabase.configuration())
        if let preferences = stage.settings {
            return try await maintenance.withAccess {
                try await self.finishPendingSettings()
                return try await self.visuals.withMaintenance {
                    try await Task.detached {
                        try await self.restore(stage, from: source, settings: preferences)
                    }.value
                }
            }
        }
        do {
            return try await database.writer.write { target in
                try source.read { try PortableCSV.merge($0, into: target) }
            }
        } catch is DatabaseError {
            throw PortableDataError.conflictingRecords
        }
    }

    private func restore(_ stage: Stage, from source: DatabaseQueue, settings: PortableSettings) async throws -> PortableDataOutcome {
        var created: [URL] = []
        var committed = false
        defer {
            if !committed {
                for file in created { try? FileManager.default.removeItem(at: file) }
            }
        }
        var paths: [String: String] = [:]
        let assets = try await source.read { try VisualAssetRecord.fetchAll($0) }
        for asset in assets {
            let path = "visual_assets/\(UUID().uuidString.lowercased()).webp"
            let destination = visuals.root.appendingPathComponent(path)
            created.append(destination)
            try PortableFiles.copy(stage.directory.appendingPathComponent("payload").appendingPathComponent(asset.relative_path),
                to: destination, limit: VisualLimits.outputBytes)
            paths[asset.id] = path
        }
        let mappings = paths
        let payload = String(decoding: try settings.encoded(), as: UTF8.self)
        try await database.writer.write { target in
            try source.read { staged in
                try PortableLedger.clear(target)
                for table in PortableLedger.tables {
                    try PortableLedger.copy(table, from: staged, to: target, images: mappings)
                }
                try PortableLedger.checkReferences(target)
                try target.execute(sql: "INSERT OR REPLACE INTO restore_state(id, settings) VALUES (1, ?)", arguments: [payload])
            }
        }
        committed = true
        var pending = false
        do { try await finishPendingSettings() }
        catch { pending = true }
        return PortableDataOutcome(imported: stage.preview.transactions, skipped: 0, settingsPending: pending)
    }

    func discard(_ token: UUID) {
        if let stage = pending.removeValue(forKey: token) {
            try? FileManager.default.removeItem(at: stage.directory)
        }
    }

    func discardExport(_ file: URL) {
        if exports.remove(file) != nil { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    }

    private func newDirectory(id: UUID = UUID()) throws -> URL {
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try PortableFiles.directory(directory)
        return directory
    }

    private static func csvColumns() throws -> [String] {
        guard let columns = try AndroidExchangeSchema.load().columns[String(AndroidExchangeSchema.current)]?["transactions"] else {
            throw PortableDataError.unsupportedSchema
        }
        return columns
    }
}
