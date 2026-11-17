import Foundation
import Testing
@testable import Cost

actor MemoryEntryDraftStore: EntryDraftStore {
    var values: [String: EntryDraft] = [:]
    func load(key: String) -> EntryDraft? { values[key] }
    func save(_ draft: EntryDraft, key: String) { values[key] = draft }
    func remove(key: String) { values.removeValue(forKey: key) }
}

@MainActor
struct LedgerFeatureTests {
    func fixture() async throws -> LedgerViewModel {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let services = LedgerServices(currencies: repo, categories: repo, accounts: repo, tags: repo, transactions: repo, funds: repo, drafts: MemoryEntryDraftStore())
        let vm = LedgerViewModel(services: services, environment: LedgerEnvironment(now: { 1_800_000_000_000 }, newID: { UUID().uuidString }, zoneID: { "Asia/Singapore" }))
        await vm.reload()
        return vm
    }
    @Test func addEditDeleteUndoUsesRealRepositoriesAndFrozenSnapshot() async throws {
        let vm = try await fixture()
        let entry = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment)
        await entry.load()
        entry.draft.amount = "12.34"
        entry.draft.note = "中文输入保持原文"
        #expect(await entry.save())
        await vm.reload()
        let first = try #require(vm.rows.first)
        #expect(first.original.minorUnits == 1234 && first.original == first.convertedBase)
        #expect(first.exchangeRate.method == .identity && first.exchangeRate.providerID == "IDENTITY")
        #expect(first.occurredAt.zoneID == "Asia/Singapore")
        let edit = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment, existing: first)
        await edit.load(); edit.draft.amount = "20.01"
        #expect(await edit.save())
        await vm.reload()
        let edited = try #require(vm.rows.first)
        #expect(edited.id == first.id && edited.requestKey == first.requestKey && edited.original.minorUnits == 2001)
        await vm.delete(edited)
        #expect(vm.rows.isEmpty && vm.undoID == first.id)
        await vm.restore(id: first.id)
        #expect(vm.rows.first?.original.minorUnits == 2001 && vm.undoID == nil)
    }
    @Test func invalidInputAndForeignCurrencyKeepDraftAndRequestKey() async throws {
        let vm = try await fixture()
        let entry = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment)
        await entry.load()
        let key = entry.draft.requestKey
        entry.draft.amount = "1.001"
        #expect(await entry.save() == false)
        #expect(entry.draft.amount == "1.001" && entry.draft.requestKey == key)
        entry.draft.amount = "12.34"; entry.draft.currencyCode = "USD"
        #expect(await entry.save() == false)
        #expect(try await vm.services.transactions.recentTransactions(limit: 200).isEmpty)
        let restored = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment)
        await restored.load()
        #expect(restored.draft == entry.draft && restored.restored)
    }
    @Test func repeatedSaveIsIdempotentAndTagReusePreservesIdentity() async throws {
        let vm = try await fixture()
        let entry = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment)
        entry.draft.amount = "1.00"
        #expect(await entry.addTag(name: " ＦＯＯ  bar "))
        #expect(await entry.addTag(name: "foo\u{00A0}BAR"))
        #expect(entry.draft.tagIDs.count == 1)
        #expect(await entry.save()); #expect(await entry.save())
        #expect(try await vm.services.transactions.recentTransactions(limit: 200).count == 1)
    }
    @Test func archivedReferenceCannotBeUsedForNewBillButHistoricalEditKeepsIt() async throws {
        let vm = try await fixture()
        let entry = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment)
        entry.draft.amount = "1.00"; #expect(await entry.save())
        await vm.reload()
        let existing = try #require(vm.rows.first)
        try await vm.services.categories.archiveCategory(id: existing.categoryID, at: existing.updatedAt + 1)
        let newEntry = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment)
        newEntry.draft.amount = "2.00"
        #expect(await newEntry.save() == false)
        let edit = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment, existing: existing)
        edit.draft.note = "保留历史分类"
        #expect(await edit.save())
    }
    @Test func concurrentEditsRejectStaleExpectedVersionAndKeepText() async throws {
        let vm = try await fixture()
        let entry = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment)
        entry.draft.amount = "1.00"; #expect(await entry.save()); await vm.reload()
        let existing = try #require(vm.rows.first)
        let first = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment, existing: existing)
        let stale = EntryViewModel(services: vm.services, categories: vm.categories, accounts: vm.accounts, environment: vm.environment, existing: existing)
        first.draft.amount = "2.00"; #expect(await first.save())
        stale.draft.amount = "3.00"; #expect(await stale.save() == false)
        #expect(stale.draft.amount == "3.00" && stale.error != nil)
        #expect(try await vm.services.transactions.transaction(id: existing.id)?.original.minorUnits == 200)
    }
    @Test func metadataEditorValidatesAndDefaultArchivingAllowsNoDefault() async throws {
        let vm = try await fixture()
        let create = MetadataViewModel(ledger: vm, kind: .category, recordID: nil)
        create.name = "餐饮"; create.visual.source = .emoji; create.visual.emoji = "🍜"
        #expect(await create.save())
        let row = try #require(vm.categories.first { $0.name == "餐饮" })
        let child = MetadataViewModel(ledger: vm, kind: .category, recordID: nil)
        child.name = "午餐"; child.parentID = row.id
        #expect(await child.save())
        let archive = MetadataViewModel(ledger: vm, kind: .category, recordID: row.id)
        archive.archived = true; #expect(await archive.save())
        #expect(vm.categories.first { $0.name == "午餐" }?.isArchived == true)
        #expect(await archive.delete() == false)
        let account = MetadataViewModel(ledger: vm, kind: .account, recordID: "seed-default-account")
        account.archived = true; #expect(await account.save())
        #expect(vm.accounts.allSatisfy { !$0.isDefault })
    }
}
