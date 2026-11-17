import Foundation
import Observation

@MainActor @Observable
final class EntryViewModel {
    var draft: EntryDraft
    let existing: LedgerTransaction?
    let services: LedgerServices
    let environment: LedgerEnvironment
    let key: String
    var isBusy = false
    var error: String?
    var restored = false
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var savingDraft = false
    @ObservationIgnored private var pendingDraft: EntryDraft?
    @ObservationIgnored private var finished = false

    init(services: LedgerServices, categories: [Category], accounts: [Account], environment: LedgerEnvironment, existing: LedgerTransaction? = nil) {
        self.services = services; self.environment = environment; self.existing = existing
        key = existing?.id ?? "new"
        draft = EntryDraft(id: existing?.id ?? environment.newID(), requestKey: existing?.requestKey ?? environment.newID(),
            occurredMillis: existing?.occurredAt.epochMillis ?? environment.now(), zoneID: existing?.occurredAt.zoneID ?? environment.zoneID())
        draft.accountID = existing?.accountID ?? accounts.first { $0.isDefault && !$0.isArchived }?.id ?? accounts.first { !$0.isArchived }?.id ?? ""
        draft.categoryID = existing?.categoryID ?? categories.first { $0.type == .expense && !$0.isArchived }?.id ?? ""
        if let existing {
            draft.editingUpdatedAt = existing.updatedAt
            draft.amount = existing.original.plainText; draft.type = existing.type
            draft.currencyCode = existing.original.currencyCode.rawValue; draft.baseCurrencyCode = existing.convertedBase.currencyCode.rawValue
            draft.baseScale = existing.convertedBase.scale; draft.note = existing.note ?? ""; draft.tagIDs = existing.tagIDs
        }
    }
    func load() async {
        guard !loaded else { return }; loaded = true
        let original = draft
        do {
            if let saved = try await services.drafts.load(key: key), draft == original,
               existing == nil || (saved.id == existing?.id && saved.editingUpdatedAt == existing?.updatedAt) {
                draft = saved; restored = true
            }
        } catch { self.error = "无法恢复上次草稿，账本未改变。" }
    }
    func addTag(name: String) async -> Bool {
        do {
            guard name.count <= 120 else { throw LedgerError.invalidField("tagName") }
            let time = environment.now()
            let tag = try await services.tags.saveTag(Tag(id: environment.newID(), name: name, createdAt: time, updatedAt: time))
            draft.tagIDs.insert(tag.id)
            return true
        } catch { self.error = LedgerMessage.text(error); return false }
    }
    /// Serializes autosave so older edits never overwrite newer text/IME input.
    func persist() async {
        guard !finished else { return }
        pendingDraft = draft
        guard !savingDraft else { return }
        savingDraft = true
        defer { savingDraft = false }
        while let snapshot = pendingDraft {
            pendingDraft = nil
            do { try await services.drafts.save(snapshot, key: key) }
            catch { self.error = "草稿过大或无法保存，请缩短备注后重试。" }
        }
    }
    func save() async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; defer { isBusy = false }
        let captured = draft
        do {
            _ = try await SaveEntryUseCase(transactions: services.transactions, currencies: services.currencies, environment: environment).save(captured, existing: existing)
            finished = true; pendingDraft = nil
            await services.drafts.remove(key: key)
            return true
        } catch { self.error = LedgerMessage.text(error); await persist(); return false }
    }
}
