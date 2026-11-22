import Foundation
import GRDB
import Testing
@testable import Cost

struct MigrationTests {
    @Test
    func completeSchemaAndConstraintsAreInstalled() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { (db: Database) throws -> Void in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> 'grdb_migrations'")
            #expect(tables.count == 18)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger'") == 62)
            #expect(try Int.fetchOne(db, sql: "PRAGMA user_version") == 1)
            #expect(try Int.fetchOne(db, sql: "PRAGMA foreign_keys") == 1)
            #expect(try Int.fetchOne(db, sql: "PRAGMA application_id") == AppDatabase.applicationID)
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM currencies WHERE is_enabled = 1") == 11)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM currencies WHERE asset_type = 'CRYPTO' AND is_enabled = 0") == 4)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM account_fund_openings") == 0)
        }
    }

    @Test
    func seedMigrationDoesNotOverwriteExistingPreferencesOrMetadata() throws {
        let writer = try DatabaseQueue(configuration: AppDatabase.configuration())
        let migrator = try AppDatabase.makeMigrator()
        try migrator.migrate(writer, upTo: "v1_schema")
        try writer.write { db in
            try db.execute(sql: "INSERT INTO currencies VALUES ('CNY','FIAT','用户名称','¥',2,0,999,1)")
        }
        _ = try AppDatabase(writer: writer)
        try writer.read { (db: Database) throws -> Void in
            let currency = try #require(try CurrencyRecord.fetchOne(db, key: "CNY"))
            #expect(currency.display_name == "用户名称")
            #expect(currency.is_enabled == 0)
            #expect(currency.sort_order == 999)
        }
        try writer.write { db in
            try db.execute(sql: "UPDATE accounts SET name = '保留名称', is_archived = 1, is_default = 0 WHERE id = 'seed-default-account'")
        }
        _ = try AppDatabase(writer: writer)
        try writer.read { (db: Database) throws -> Void in
            #expect(try AccountRecord.fetchOne(db, key: "seed-default-account")?.name == "保留名称")
            #expect(try AccountRecord.fetchOne(db, key: "seed-default-account")?.is_archived == 1)
        }
    }

    @Test
    func failedSeedRollsBackAndCanBeRetried() throws {
        let writer = try DatabaseQueue(configuration: AppDatabase.configuration())
        try AppDatabase.makeMigrator().migrate(writer, upTo: "v1_schema")
        try writer.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_seed BEFORE INSERT ON accounts BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
        }
        #expect(throws: (any Error).self) { _ = try AppDatabase(writer: writer) }
        try writer.read { (db: Database) throws -> Void in
            #expect(try CurrencyRecord.fetchCount(db) == 0)
            #expect(try CategoryRecord.fetchCount(db) == 0)
            #expect(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations") == ["v1_schema"])
        }
        try writer.write { db in try db.execute(sql: "DROP TRIGGER fail_seed") }
        _ = try AppDatabase(writer: writer)
        try writer.read { (db: Database) throws -> Void in #expect(try CurrencyRecord.fetchCount(db) == 15) }
    }

    @Test
    func unknownFutureMigrationAndForeignDatabasesAreNeverErased() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('v999_future')")
        }
        #expect(throws: LedgerError.unsupportedDatabase) { _ = try AppDatabase(writer: database.writer) }
        try database.writer.read { (db: Database) throws -> Void in #expect(try CurrencyRecord.fetchCount(db) == 15) }
        let foreign = try DatabaseQueue()
        try foreign.write { db in try db.execute(sql: "CREATE TABLE keep_me(value TEXT); INSERT INTO keep_me VALUES ('preserved')") }
        #expect(throws: LedgerError.unsupportedDatabase) { _ = try AppDatabase(writer: foreign) }
        try foreign.read { (db: Database) throws -> Void in #expect(try String.fetchOne(db, sql: "SELECT value FROM keep_me") == "preserved") }
    }

    @Test
    func sqliteRejectsInexactIntegerStorageAndInvalidHierarchy() throws {
        let database = try AppDatabase.inMemory()
        #expect(throws: (any Error).self) {
            try database.writer.write { db in try db.execute(sql: "UPDATE currencies SET default_scale = 1.5 WHERE code = 'CNY'") }
        }
        #expect(throws: (any Error).self) {
            try database.writer.write { db in try db.execute(sql: "UPDATE categories SET parent_id = id WHERE id = 'seed-expense-other'") }
        }
        #expect(throws: (any Error).self) {
            try database.writer.write { db in try db.execute(sql: "UPDATE accounts SET is_archived = 1 WHERE id = 'seed-default-account'") }
        }
    }

    @Test
    func populatedV1DatabaseMigratesOnDiskAndSurvivesReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("fixture.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = try DatabaseQueue(path: url.path, configuration: AppDatabase.configuration())
        try AppDatabase.makeMigrator().migrate(legacy, upTo: "v1_schema")
        let seed = try JSONDecoder().decode(DatabaseSeed.self, from: DatabaseResources.data("CostSeedV1", extension: "json"))
        let tag = TestLedger.tag()
        let transaction = try TestLedger.transaction(code: "USD", rate: "7.250000000001", method: .manualRate,
            requestKey: "legacy-request", tags: [tag.id], note: "旧版冻结估值")
        try legacy.write { db in
            try seed.install(in: db)
            try db.execute(sql: "UPDATE accounts SET name = '旧版账户' WHERE id = 'seed-default-account'")
            try TagRecord(tag).insert(db)
            try GRDBLedgerRepository.insertTransaction(db, transaction)
        }
        try legacy.close()

        for _ in 0..<2 {
            let opened = try await AppDatabase.open(at: url)
            defer { try? opened.writer.close() }
            let repository = GRDBLedgerRepository(database: opened)
            #expect(try await repository.transaction(requestKey: "legacy-request") == transaction)
            #expect(try await repository.account(id: transaction.accountID)?.name == "旧版账户")
            try await opened.writer.read { (db: Database) throws -> Void in
                #expect(try String.fetchOne(db, sql: "PRAGMA journal_mode") == "wal")
                #expect(try String.fetchAll(db, sql: "PRAGMA integrity_check") == ["ok"])
                #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
                let migrations = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
                #expect(migrations == ["v1_schema", "v1_seed"])
                #expect(try TransactionRecord.fetchCount(db) == 1)
            }
        }
    }
}
