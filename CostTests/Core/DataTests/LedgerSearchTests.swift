import Testing
@testable import Cost

struct LedgerSearchTests {
    @Test func searchFiltersPagingAndSoftDeleteApplyBeforeLimit() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let tag = try await repo.saveTag(TestLedger.tag(name: "通勤"))
        for index in 0..<7 {
            _ = try await repo.createTransaction(TestLedger.transaction(id: "bill-\(index)", occurred: Int64(index + 1) * 86400000,
                tags: index % 2 == 0 ? [tag.id] : [], note: index % 2 == 0 ? "地铁" : "Other"))
        }
        _ = try await repo.softDeleteTransaction(id: "bill-6", at: 20)
        var query = LedgerQuery(); query.limit = 2
        let first = try await repo.searchTransactions(query)
        #expect(first.rows.map(\.id) == ["bill-5", "bill-4"])
        query.cursor = first.next
        let second = try await repo.searchTransactions(query)
        #expect(second.rows.map(\.id) == ["bill-3", "bill-2"])
        query = LedgerQuery(); query.text = "地铁"; query.tagID = tag.id; query.startDay = 2; query.endDayExclusive = 6
        #expect(try await repo.searchTransactions(query).rows.map(\.id) == ["bill-4", "bill-2"])
        query = LedgerQuery(); query.text = "通勤"
        #expect(try await repo.searchTransactions(query).rows.count == 3)
        query = LedgerQuery(); query.deletedOnly = true
        #expect(try await repo.searchTransactions(query).rows.map(\.id) == ["bill-6"])
        query.text = "%' OR 1=1 --"
        #expect(try await repo.searchTransactions(query).rows.isEmpty)
    }
    @Test func tiedTimeUsesStableIDCursorAndParentFilterIncludesChild() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        try await repo.saveCategory(Category(id: "child", name: "子分类", type: .expense, parentID: "seed-expense-other", createdAt: 10, updatedAt: 10))
        for id in ["a", "b", "c"] { _ = try await repo.createTransaction(TestLedger.transaction(id: id, category: "child")) }
        var query = LedgerQuery(); query.categoryID = "seed-expense-other"; query.limit = 2
        let page = try await repo.searchTransactions(query)
        #expect(page.rows.map(\.id) == ["c", "b"])
        query.cursor = page.next
        #expect(try await repo.searchTransactions(query).rows.map(\.id) == ["a"])
    }
}
