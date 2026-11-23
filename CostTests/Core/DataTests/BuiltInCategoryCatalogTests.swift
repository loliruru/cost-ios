import GRDB
import Testing
@testable import Cost

struct BuiltInCategoryCatalogTests {
    @Test func newLedgerIncludesTheTwoLevelCatalog() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let categories = try await repository.categories()
        #expect(categories.count == 36)
        #expect(categories.filter { $0.type == .expense && $0.parentID != nil }.count == 21)
        #expect(categories.filter { $0.type == .income && $0.parentID != nil }.count == 2)
        #expect(categories.filter { $0.type == .expense && $0.parentID == nil }.map(\.name)
            == ["其他支出", "餐饮", "交通", "住房", "数码硬件", "数字服务", "娱乐", "日常生活", "金融费用"])
        #expect(categories.filter { $0.type == .income && $0.parentID == nil }.map(\.name)
            == ["其他收入", "回款", "工资奖金", "投资收益"])
        let snacks = try #require(try await repository.category(id: "seed-category-chips"))
        #expect(snacks.name == "零食饮品")
        #expect(snacks.parentID == "seed-category-dining")
        #expect(snacks.visual.iconKey == "category-chips")
        #expect(try await repository.category(id: "seed-category-refund")?.parentID == "seed-category-returns")
    }

    @Test func addingToAnExistingLedgerReusesItsCategoriesAndKeepsItsTransactions() async throws {
        let repository = try oldLedger()
        let dining = Category(id: "custom-dining", name: "餐饮", type: .expense,
            visual: LedgerVisual(iconKey: "fork.knife"), sortOrder: 7, createdAt: 1, updatedAt: 1)
        let meals = Category(id: "custom-meals", name: "三餐", type: .expense, parentID: dining.id,
            createdAt: 1, updatedAt: 1)
        let traffic = Category(id: "custom-traffic", name: "交通", type: .expense, isArchived: true,
            createdAt: 1, updatedAt: 1)
        try await repository.saveCategory(dining)
        try await repository.saveCategory(meals)
        try await repository.saveCategory(traffic)
        let transaction = try TestLedger.transaction(category: meals.id)
        _ = try await repository.createTransaction(transaction)

        async let first = repository.installBuiltInCategories()
        async let second = repository.installBuiltInCategories()
        let counts = try await (first, second)
        #expect(Set([counts.0, counts.1]) == Set([0, 28]))
        #expect(try await repository.category(id: dining.id) == dining)
        #expect(try await repository.category(id: meals.id) == meals)
        #expect(try await repository.category(id: traffic.id) == traffic)
        #expect(try await repository.category(id: "seed-category-chips:custom-dining")?.parentID == dining.id)
        #expect(try await repository.category(id: "seed-category-dining") == nil)
        #expect(try await repository.category(id: "seed-category-metro") == nil)
        #expect(try await repository.transaction(id: transaction.id) == transaction)
    }

    @Test func catalogWriteRollsBackAndUsesTheSameMetadataAsFreshInitialization() async throws {
        let repository = try oldLedger()
        let before = try await repository.categories(includeArchived: true)
        #expect(before.count == 2)
        try await repository.database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_catalog BEFORE INSERT ON categories
                WHEN NEW.id = 'seed-category-finance'
                BEGIN SELECT RAISE(ABORT, 'fixture catalog failure'); END
                """)
        }
        await #expect(throws: (any Error).self) { try await repository.installBuiltInCategories() }
        #expect(try await repository.categories(includeArchived: true) == before)
        try await repository.database.writer.write { db in try db.execute(sql: "DROP TRIGGER fail_catalog") }
        #expect(try await repository.installBuiltInCategories() == 34)

        let fresh = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let freshCategories = try await fresh.categories(includeArchived: true)
        #expect(try await repository.categories(includeArchived: true) == freshCategories)
        #expect(before.allSatisfy(freshCategories.contains))
    }

    private func oldLedger() throws -> GRDBLedgerRepository {
        let writer = try DatabaseQueue(configuration: AppDatabase.configuration())
        try AppDatabase.makeMigrator().migrate(writer, upTo: "v1_schema")
        let seed = try DatabaseSeed.loadV1()
        try writer.write { db in
            try seed.install(in: db)
            try db.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('v1_seed')")
        }
        return GRDBLedgerRepository(database: try AppDatabase(writer: writer))
    }
}
