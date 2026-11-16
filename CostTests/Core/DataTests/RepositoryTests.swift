import GRDB
import Testing
@testable import Cost

struct RepositoryTests {
    @Test
    func metadataCrudAndDefaultSwitchAreAtomic() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        #expect(try await repository.currencies().count == 15)
        var currency = try #require(try await repository.currency(code: CurrencyCode("USD")))
        currency.isEnabled = false
        try await repository.saveCurrency(currency)
        #expect(try await repository.currencies(includeDisabled: false).count == 10)
        currency.assetType = .crypto
        await #expect(throws: LedgerError.invalidCurrencyType) { try await repository.saveCurrency(currency) }
        let account = try Account(id: "new-default", name: "新默认账户", currencyCode: CurrencyCode("CNY"), isDefault: true, createdAt: 10, updatedAt: 10)
        try await repository.saveAccount(account)
        #expect(try await repository.accounts().filter(\.isDefault).map(\.id) == ["new-default"])
        let invalid = try Account(id: "missing-currency", name: "无效账户", currencyCode: CurrencyCode("ZZZ"), isDefault: true, createdAt: 20, updatedAt: 20)
        await #expect(throws: LedgerError.storageConstraint) { try await repository.saveAccount(invalid) }
        #expect(try await repository.accounts().filter(\.isDefault).map(\.id) == ["new-default"])
    }

    @Test
    func categoryHierarchyArchiveAndGuardedDeletion() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let parent = Category(id: "parent", name: "一级", type: .expense, createdAt: 10, updatedAt: 10)
        let child = Category(id: "child", name: "二级", type: .expense, parentID: "parent", createdAt: 10, updatedAt: 10)
        try await repository.saveCategory(parent)
        try await repository.saveCategory(child)
        let third = Category(id: "third", name: "三级不允许", type: .expense, parentID: "child", createdAt: 10, updatedAt: 10)
        await #expect(throws: LedgerError.invalidHierarchy) { try await repository.saveCategory(third) }
        #expect(try await repository.deleteArchivedCategory(id: "parent") == .notArchived)
        try await repository.archiveCategory(id: "parent", at: 20)
        #expect(try await repository.category(id: "child")?.isArchived == true)
        #expect(try await repository.deleteArchivedCategory(id: "parent") == .hasChildren)
        var restoredChild = child
        restoredChild.updatedAt = 30
        await #expect(throws: LedgerError.invalidHierarchy) { try await repository.saveCategory(restoredChild) }
        #expect(try await repository.deleteArchivedCategory(id: "child") == .deleted)
        #expect(try await repository.deleteArchivedCategory(id: "parent") == .deleted)
        #expect(try await repository.deleteArchivedCategory(id: "missing") == .notFound)
    }

    @Test
    func tagNormalizationReusesAndRestoresIdentityWithoutRenaming() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let original = TestLedger.tag(id: "old", name: "ＦＯＯ  Bar", archived: true)
        _ = try await repository.saveTag(original)
        var proposed = TestLedger.tag(id: "new", name: " foo\u{00A0}bar ", updated: 20)
        proposed.colorKey = "blue"
        let reused = try await repository.saveTag(proposed)
        #expect(reused.id == original.id && reused.name == original.name)
        #expect(reused.colorKey == original.colorKey && !reused.isArchived)
        #expect(try await repository.tag(id: "new") == nil)
    }

    @Test
    func transactionCrudSoftDeletionAndHalfOpenRange() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let tag = try await repository.saveTag(TestLedger.tag())
        let first = try TestLedger.transaction(requestKey: "save-once", tags: [tag.id])
        #expect(try await repository.createTransaction(first) == first)
        #expect(try await repository.transaction(id: first.id) == first)
        #expect(try await repository.transaction(requestKey: "save-once") == first)
        let nextDay = try TestLedger.transaction(id: "next-day", occurred: 2 * 86_400_000)
        _ = try await repository.createTransaction(nextDay)
        #expect(try await repository.transactions(startEpochDay: 1, endEpochDayExclusive: 2).map(\.id) == [first.id])
        let edited = try TestLedger.transaction(units: 2000, requestKey: "save-once", updated: 20, tags: [], note: "edited")
        #expect(try await repository.updateTransaction(edited, expectedUpdatedAt: 10))
        #expect(try await repository.transaction(id: first.id) == edited)
        await #expect(throws: LedgerError.conflict) { _ = try await repository.updateTransaction(edited, expectedUpdatedAt: 10) }
        #expect(try await repository.softDeleteTransaction(id: first.id, at: 30))
        #expect(try await repository.softDeleteTransaction(id: first.id, at: 31) == false)
        #expect(try await repository.recentTransactions().map(\.id) == [nextDay.id])
        #expect(try await repository.transaction(id: first.id)?.original.minorUnits == 2000)
        #expect(try await repository.restoreTransaction(id: first.id, at: 40))
        #expect(try await repository.restoreTransaction(id: first.id, at: 41) == false)
        #expect(try await repository.recentTransactions().count == 2)
    }

    @Test
    func failedTagAssociationRollsBackBothInsertAndUpdate() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let invalid = try TestLedger.transaction(tags: ["missing"])
        await #expect(throws: LedgerError.storageConstraint) { _ = try await repository.createTransaction(invalid) }
        #expect(try await repository.transaction(id: invalid.id) == nil)
        let tag = try await repository.saveTag(TestLedger.tag())
        let original = try TestLedger.transaction(tags: [tag.id])
        _ = try await repository.createTransaction(original)
        let update = try TestLedger.transaction(units: 2222, updated: 20, tags: ["missing"])
        await #expect(throws: LedgerError.storageConstraint) { _ = try await repository.updateTransaction(update, expectedUpdatedAt: 10) }
        #expect(try await repository.transaction(id: original.id) == original)
    }

    @Test
    func concurrentRequestRetriesCreateExactlyOneTransaction() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<20 {
                group.addTask {
                    try await repository.createTransaction(TestLedger.transaction(id: "request-\(index)", requestKey: "same-request")).id
                }
            }
            var ids = Set<String>()
            for try await id in group { ids.insert(id) }
            return ids
        }
        #expect(ids.count == 1)
        #expect(try await repository.recentTransactions().count == 1)
    }

    @Test
    func deletedTransactionsStillProtectCategoryAndArchivePreservesLinks() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let tag = try await repository.saveTag(TestLedger.tag())
        let transaction = try TestLedger.transaction(tags: [tag.id])
        _ = try await repository.createTransaction(transaction)
        try await repository.archiveCategory(id: transaction.categoryID, at: 20)
        #expect(try await repository.transaction(id: transaction.id) == transaction)
        _ = try await repository.softDeleteTransaction(id: transaction.id, at: 20)
        #expect(try await repository.deleteArchivedCategory(id: transaction.categoryID) == .inUse)
    }

    @Test
    func archivedTagDeletionRollsBackOnFailureAndKeepsOwningTransactions() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLedgerRepository(database: database)
        let tag = try await repository.saveTag(TestLedger.tag())
        let transaction = try TestLedger.transaction(tags: [tag.id])
        _ = try await repository.createTransaction(transaction)
        #expect(try await repository.deleteArchivedTag(id: tag.id) == false)
        _ = try await repository.saveTag(TestLedger.tag(archived: true, updated: 20))
        try await database.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_tag_delete BEFORE DELETE ON tags BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
        }
        await #expect(throws: LedgerError.storageConstraint) { _ = try await repository.deleteArchivedTag(id: tag.id) }
        #expect(try await repository.transaction(id: transaction.id) == transaction)
        try await database.writer.write { db in try db.execute(sql: "DROP TRIGGER fail_tag_delete") }
        #expect(try await repository.deleteArchivedTag(id: tag.id))
        let preserved = try #require(try await repository.transaction(id: transaction.id))
        #expect(preserved.original == transaction.original && preserved.tagIDs.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func databaseObservationPublishesCommittedChanges() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        var iterator = repository.observeRecentTransactions().makeAsyncIterator()
        #expect(try await iterator.next() == [])
        let value = try TestLedger.transaction()
        _ = try await repository.createTransaction(value)
        #expect(try await iterator.next() == [value])
    }

    @Test
    func managedInvestmentProfitCannotBeChangedIndependently() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLedgerRepository(database: database)
        try await repository.saveAccount(Account(id: "investment", name: "测试投资账户", createdAt: 10, updatedAt: 10))
        let profit = try TestLedger.transaction(units: 100, category: "seed-income-other", type: .income)
        _ = try await repository.createTransaction(profit)
        try await database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO account_transfers VALUES (
                    'transfer','transfer-request','investment','seed-default-account',
                    'INVESTMENT_COST','AVAILABLE','CNY',2,1000,100,'seed-income-other',?,
                    86400000,'UTC',NULL,10,10,NULL)
                """, arguments: [profit.id])
        }
        await #expect(throws: LedgerError.managedTransaction) { _ = try await repository.updateTransaction(profit, expectedUpdatedAt: 10) }
        await #expect(throws: LedgerError.managedTransaction) { _ = try await repository.softDeleteTransaction(id: profit.id, at: 20) }
        await #expect(throws: LedgerError.managedTransaction) { _ = try await repository.restoreTransaction(id: profit.id, at: 20) }
        #expect(try await repository.transaction(id: profit.id) == profit)
    }
}
