import Foundation
import GRDB
import Testing
@testable import Cost

struct QuickTemplateTests {
    private func useCase(_ repository: GRDBLedgerRepository, at timestamp: Int64 = 100, id: String? = nil) -> ManageQuickTemplatesUseCase {
        ManageQuickTemplatesUseCase(templates: repository, transactions: repository, currencies: repository,
            categories: repository, accounts: repository, tags: repository,
            environment: LedgerEnvironment(now: { timestamp }, newID: { id ?? UUID().uuidString }, zoneID: { "Asia/Singapore" }))
    }

    private func input(code: String = "CNY", tags: Set<String> = [], order: Int64? = nil) -> QuickTemplateDraft {
        QuickTemplateDraft(name: "  验收　午餐 ", iconKey: "receipt", amount: "12.34", currencyCode: code,
            categoryID: "seed-expense-other", accountID: "seed-default-account", note: "  备注  ", tagIDs: tags, sortOrder: order)
    }

    private func recorded(_ action: QuickTemplateAction) throws -> LedgerTransaction {
        if case .recorded(let row) = action { return row }
        throw LedgerError.invalidSnapshot
    }

    @Test func concurrentKeyRecordsExactlyOneBillAndOneUse() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let tag = try await repo.saveTag(TestLedger.tag())
        let template = try await useCase(repo, id: "lunch").save(input(tags: [tag.id]))
        let action = useCase(repo, at: 200)
        let bills = try await withThrowingTaskGroup(of: LedgerTransaction.self) { group in
            for _ in 0..<20 {
                group.addTask { try recorded(await action.record(templateID: template.id, requestID: "tap")) }
            }
            var result: [LedgerTransaction] = []
            for try await bill in group { result.append(bill) }
            return result
        }
        let bill = try #require(bills.first)
        #expect(bills.allSatisfy { $0 == bill })
        #expect(try await repo.recentTransactions() == [bill])
        #expect(bill.original.minorUnits == 1234)
        #expect(bill.convertedBase == bill.original && bill.exchangeRate.method == .identity)
        #expect(bill.source == .template && bill.sourceID == template.id)
        #expect(bill.occurredAt.epochMillis == 200 && bill.occurredAt.zoneID == "Asia/Singapore")
        #expect(bill.tagIDs == [tag.id] && bill.note == "备注")
        let saved = try #require(try await repo.quickTemplate(id: template.id))
        #expect(saved.content.name == "验收 午餐")
        #expect(saved.usageCount == 1 && saved.lastUsedAt == 200)
    }

    @Test func undoRecomputesLastUseAndRetryCannotResurrectBill() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let template = try await useCase(repo).save(input())
        let first = try recorded(await useCase(repo, at: 200).record(templateID: template.id, requestID: "first"))
        let second = try recorded(await useCase(repo, at: 300).record(templateID: template.id, requestID: "second"))
        #expect(try await repo.softDeleteTransaction(id: second.id, at: 400))
        #expect(try await repo.softDeleteTransaction(id: second.id, at: 401) == false)
        let afterUndo = try #require(try await repo.quickTemplate(id: template.id))
        #expect(afterUndo.usageCount == 1 && afterUndo.lastUsedAt == first.createdAt)
        let retry = try recorded(await useCase(repo, at: 500).record(templateID: template.id, requestID: "second"))
        #expect(retry.id == second.id && retry.deletedAt == 400)
        #expect(try await repo.recentTransactions() == [first])
        #expect(try await repo.restoreTransaction(id: second.id, at: 600))
        let restored = try #require(try await repo.quickTemplate(id: template.id))
        #expect(restored.usageCount == 2 && restored.lastUsedAt == 300)
        #expect(try await repo.softDeleteTransaction(id: first.id, at: 700))
        #expect(try await repo.softDeleteTransaction(id: second.id, at: 800))
        let empty = try #require(try await repo.quickTemplate(id: template.id))
        #expect(empty.usageCount == 0 && empty.lastUsedAt == nil)
    }

    @Test func usageFailureRollsBackBillTagsAndUndo() async throws {
        let db = try AppDatabase.inMemory()
        let repo = GRDBLedgerRepository(database: db)
        let tag = try await repo.saveTag(TestLedger.tag())
        let template = try await useCase(repo).save(input(tags: [tag.id]))
        let action = useCase(repo, at: 200)
        try await db.writer.write { database in
            try database.execute(sql: """
                CREATE TRIGGER test_reject_template_use BEFORE UPDATE OF usage_count ON quick_templates
                BEGIN SELECT RAISE(ABORT, 'fixture failure'); END
                """)
        }
        await #expect(throws: LedgerError.storageConstraint) {
            _ = try await action.record(templateID: template.id, requestID: "atomic")
        }
        #expect(try await repo.quickTemplate(id: template.id) == template)
        #expect(try await repo.recentTransactions().isEmpty)
        let tagCount = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM transaction_tags") }
        #expect(tagCount == 0)
        try await db.writer.write { try $0.execute(sql: "DROP TRIGGER test_reject_template_use") }
        let bill = try recorded(await action.record(templateID: template.id, requestID: "atomic"))
        try await db.writer.write { database in
            try database.execute(sql: """
                CREATE TRIGGER test_reject_template_undo BEFORE UPDATE OF usage_count ON quick_templates
                WHEN NEW.usage_count < OLD.usage_count
                BEGIN SELECT RAISE(ABORT, 'fixture failure'); END
                """)
        }
        await #expect(throws: LedgerError.storageConstraint) { _ = try await repo.softDeleteTransaction(id: bill.id, at: 300) }
        #expect(try await repo.recentTransactions() == [bill])
        #expect(try await repo.quickTemplate(id: template.id)?.usageCount == 1)
    }

    @Test func fourLevelOrderAndAppendDefaultAreStable() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let fixtures: [(String, Int64, [Int64])] = [
            ("old-b", 20, [200]), ("recent", 20, [300]), ("priority", 10, []),
            ("old-a", 20, [200]), ("frequent", 20, [140, 150]), ("unused", 20, [])
        ]
        for (id, order, times) in fixtures {
            let template = try await useCase(repo, id: id).save(input(order: order))
            for time in times {
                _ = try await useCase(repo, at: time).record(templateID: template.id, requestID: "\(id)-\(time)")
            }
        }
        let appended = try await useCase(repo, id: "append").save(input())
        #expect(appended.sortOrder == 30)
        let rows = try await repo.quickTemplates()
        #expect(rows.map(\.id) == ["priority", "frequent", "recent", "old-a", "old-b", "unused", "append"])
    }

    @Test func archivedReferencesBlockUseAndDeletingTemplateKeepsItsBill() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        var tag = try await repo.saveTag(TestLedger.tag())
        let template = try await useCase(repo, id: "keep-history").save(input(tags: [tag.id]))
        let bill = try recorded(await useCase(repo, at: 200).record(templateID: template.id, requestID: "before-archive"))
        tag.isArchived = true
        tag.updatedAt += 1
        _ = try await repo.saveTag(tag)
        await #expect(throws: QuickTemplateError.tagUnavailable) {
            _ = try await useCase(repo).record(templateID: template.id, requestID: "blocked")
        }
        var editedInput = input()
        editedInput.name = "替换引用"
        let current = try #require(try await repo.quickTemplate(id: template.id))
        let edited = try await useCase(repo, at: 300).save(editedInput, editing: current)
        #expect(edited.content.tagIDs.isEmpty && edited.usageCount == 1)
        try await repo.setQuickTemplateArchived(id: edited.id, archived: true, expectedUpdatedAt: edited.updatedAt, at: 400)
        await #expect(throws: QuickTemplateError.unavailable) {
            _ = try await useCase(repo).entryDraft(templateID: template.id)
        }
        let archived = try #require(try await repo.quickTemplate(id: edited.id))
        try await repo.setQuickTemplateArchived(id: archived.id, archived: false, expectedUpdatedAt: archived.updatedAt, at: 500)
        let restored = try #require(try await repo.quickTemplate(id: edited.id))
        #expect(!restored.isArchived)
        try await repo.deleteQuickTemplate(id: restored.id, expectedUpdatedAt: restored.updatedAt)
        #expect(try await repo.quickTemplate(id: restored.id) == nil)
        #expect(try await repo.transaction(id: bill.id) == bill)
        #expect(try await repo.softDeleteTransaction(id: bill.id, at: 600))
        #expect(try await repo.restoreTransaction(id: bill.id, at: 700))
        #expect(try await repo.transaction(id: bill.id)?.sourceID == "keep-history")
    }

    @Test func editingPrefillDoesNotChangeTemplateAndForeignFallbackWritesNothing() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let use = useCase(repo)
        let template = try await use.save(input())
        var draft = try await use.entryDraft(templateID: template.id)
        draft.amount = "25.67"
        draft.note = "账单专属备注"
        let save = SaveEntryUseCase(transactions: repo, currencies: repo, environment: use.environment)
        let bill = try await save.save(draft)
        #expect(bill.original.minorUnits == 2567 && bill.note == "账单专属备注")
        #expect(bill.source == .template && bill.sourceID == template.id)
        #expect(try await repo.quickTemplate(id: template.id) == template)
        #expect(try await repo.softDeleteTransaction(id: bill.id, at: 300))
        #expect(try await repo.quickTemplate(id: template.id) == template)
        let usd = try await use.save(input(code: "USD"))
        let outcome = try await use.record(templateID: usd.id, requestID: "foreign")
        guard case .needsValuation(let foreign) = outcome else { Issue.record("Foreign template wrote a transaction without valuation"); return }
        #expect(foreign.amount == "12.34" && foreign.currencyCode == "USD")
        #expect(foreign.sourceTemplateID == usd.id && foreign.baseCurrencyCode == "CNY")
        await #expect(throws: LedgerError.invalidSnapshot) { _ = try await save.save(foreign) }
        #expect(try await repo.recentTransactions().isEmpty)
        #expect(try await repo.quickTemplate(id: usd.id) == usd)
        await #expect(throws: QuickTemplateError.currencyUnavailable) { _ = try await use.save(input(code: "BTC")) }
        await #expect(throws: NumericError.tooManyFractionDigits) { _ = try await use.save(input(code: "JPY")) }
    }
}
