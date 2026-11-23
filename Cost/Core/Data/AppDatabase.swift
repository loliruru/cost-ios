import Foundation
import GRDB

private final class DatabaseResourceMarker: NSObject {}

enum DatabaseResources {
    static func data(_ name: String, extension suffix: String) throws -> Data {
        guard let url = Bundle(for: DatabaseResourceMarker.self).url(forResource: name, withExtension: suffix) else {
            throw LedgerError.missingResource
        }
        return try Data(contentsOf: url)
    }
}

struct DatabaseSeed: Decodable, Sendable {
    let currencies: [CurrencyRecord]
    let categories: [CategoryRecord]
    let accounts: [AccountRecord]

    static func loadV1() throws -> Self {
        try JSONDecoder().decode(Self.self, from: DatabaseResources.data("CostSeedV1", extension: "json"))
    }

    func install(in db: Database) throws {
        for record in currencies { try record.insert(db, onConflict: .ignore) }
        for record in categories { try record.insert(db, onConflict: .ignore) }
        for record in accounts { try record.insert(db, onConflict: .ignore) }
    }
}

/// SQLite implementation only; callers receive Domain repository protocols from the composition root.
final class AppDatabase: Sendable {
    static let applicationID = 1_129_272_137
    static let migrationIDs: Set<String> = ["v1_schema", "v1_seed"]
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.preflight(writer)
        try Self.makeMigrator().migrate(writer)
    }

    static func configuration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in db.add(function: FrozenMinorSum.function) }
        return config
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue(configuration: configuration()))
    }

    static func open(at url: URL) async throws -> AppDatabase {
        try await Task.detached(priority: .userInitiated) {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var resourceDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try resourceDirectory.setResourceValues(values)
            return try AppDatabase(writer: DatabasePool(path: url.path, configuration: configuration()))
        }.value
    }

    static func openDefault() async throws -> AppDatabase {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return try await open(at: support.appendingPathComponent("Cost", isDirectory: true).appendingPathComponent("cost.sqlite"))
    }

    static func makeMigrator() throws -> DatabaseMigrator {
        let sqlData = try DatabaseResources.data("CostSchemaV1", extension: "sql")
        guard let sql = String(data: sqlData, encoding: .utf8) else { throw LedgerError.missingResource }
        let seed = try DatabaseSeed.loadV1()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_schema") { db in try db.execute(sql: sql) }
        migrator.registerMigration("v1_seed") { db in
            let isNew = try (CategoryRecord.fetchCount(db) == 0 && AccountRecord.fetchCount(db) == 0)
            try seed.install(in: db)
            if isNew { _ = try GRDBLedgerRepository.installBuiltInCategories(db) }
        }
        return migrator
    }

    private static func preflight(_ writer: any DatabaseWriter) throws {
        try writer.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
            let applicationID = try Int.fetchOne(db, sql: "PRAGMA application_id") ?? 0
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            guard version <= 1, applicationID == 0 || applicationID == Self.applicationID else { throw LedgerError.unsupportedDatabase }
            guard !tables.isEmpty else { return }
            guard try db.tableExists("grdb_migrations") else { throw LedgerError.unsupportedDatabase }
            let applied = Set(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations"))
            guard applied.isSubset(of: migrationIDs) else { throw LedgerError.unsupportedDatabase }
            if applicationID == 0 && (!applied.isEmpty || Set(tables) != ["grdb_migrations"]) {
                throw LedgerError.unsupportedDatabase
            }
        }
    }
}
