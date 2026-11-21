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
    private(set) var offer: ValuationOffer?
    var acceptsFallback = false
    @ObservationIgnored private var offeredBasis: QuoteBasis?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var savingDraft = false
    @ObservationIgnored private var pendingDraft: EntryDraft?
    @ObservationIgnored private var finished = false

    init(services: LedgerServices, categories: [Category], accounts: [Account], environment: LedgerEnvironment,
         baseCurrency: Currency? = nil,
         existing: LedgerTransaction? = nil, prefilled: EntryDraft? = nil) {
        self.services = services; self.environment = environment; self.existing = existing
        key = existing?.id ?? prefilled?.sourceTemplateID.map { "template:\($0)" } ?? "new"
        draft = EntryDraft(id: existing?.id ?? environment.newID(), requestKey: existing?.requestKey ?? environment.newID(),
            occurredMillis: existing?.occurredAt.epochMillis ?? environment.now(), zoneID: existing?.occurredAt.zoneID ?? environment.zoneID())
        if let baseCurrency {
            draft.baseCurrencyCode = baseCurrency.code.rawValue
            draft.currencyCode = baseCurrency.code.rawValue
            draft.baseScale = baseCurrency.defaultScale
        }
        draft.accountID = existing?.accountID ?? accounts.first { $0.isDefault && !$0.isArchived }?.id ?? accounts.first { !$0.isArchived }?.id ?? ""
        draft.categoryID = existing?.categoryID ?? categories.first { $0.type == .expense && !$0.isArchived }?.id ?? ""
        if let existing {
            draft.editingUpdatedAt = existing.updatedAt
            draft.amount = existing.original.plainText; draft.type = existing.type
            draft.currencyCode = existing.original.currencyCode.rawValue; draft.baseCurrencyCode = existing.convertedBase.currencyCode.rawValue
            draft.baseScale = existing.convertedBase.scale; draft.note = existing.note ?? ""; draft.tagIDs = existing.tagIDs
        }
        if let prefilled { draft = prefilled }
    }

    struct QuoteBasis: Equatable {
        let original: String
        let base: String
        let day: Int64?
        let zone: String
    }

    var quoteBasis: QuoteBasis {
        QuoteBasis(original: draft.currencyCode, base: draft.baseCurrencyCode,
            day: (try? OccurredAt(epochMillis: draft.occurredMillis, zoneID: draft.zoneID))?.localEpochDay, zone: draft.zoneID)
    }

    func clearOffer() {
        offer = nil
        offeredBasis = nil
        acceptsFallback = false
    }

    func selectCurrency(_ code: String) {
        guard draft.currencyCode != code else { return }
        draft.currencyCode = code
        draft.actualBaseAmount = nil
        draft.manualRate = nil
        clearOffer()
    }

    func fetchOffer() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        clearOffer()
        do { _ = try await requestOffer(refresh: true) }
        catch is CancellationError { }
        catch { self.error = LedgerMessage.text(error) }
    }

    private func requestOffer(refresh: Bool) async throws -> ValuationOffer {
        let captured = draft
        let basis = quoteBasis
        let code = try CurrencyCode(captured.currencyCode)
        guard let quotes = services.quotes, let currency = try await services.currencies.currency(code: code) else {
            throw QuoteFailure.notConfigured
        }
        guard refresh || currency.assetType == .fiat else { throw QuoteFailure.confirmationRequired }
        let offered = try await quotes.offer(original: code, base: CurrencyCode(captured.baseCurrencyCode),
            type: currency.assetType, occurredAt: OccurredAt(epochMillis: captured.occurredMillis, zoneID: captured.zoneID), refresh: refresh)
        guard basis == quoteBasis else { throw CancellationError() }
        offer = offered
        offeredBasis = basis
        acceptsFallback = false
        return offered
    }
    func load() async {
        guard !loaded else { return }; loaded = true
        let original = draft
        do {
            if let saved = try await services.drafts.load(key: key), draft == original,
               saved.sourceTemplateID == original.sourceTemplateID,
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
            let save = SaveEntryUseCase(transactions: services.transactions, currencies: services.currencies, environment: environment)
            var selected = offeredBasis == quoteBasis ? offer : nil
            if let previous = selected, previous != previous.at(environment.now()) {
                selected = previous.at(environment.now())
                offer = selected
                acceptsFallback = false
            }
            do {
                _ = try await save.save(captured, existing: existing, offer: selected, confirmed: acceptsFallback)
            } catch QuoteFailure.notConfigured {
                let offered = try await requestOffer(refresh: false)
                guard draft == captured else { return false }
                if offered.requiresConfirmation { return false }
                _ = try await save.save(captured, existing: existing, offer: offered)
            }
            finished = true; pendingDraft = nil
            await services.drafts.remove(key: key)
            return true
        } catch is CancellationError { return false }
        catch { self.error = LedgerMessage.text(error); await persist(); return false }
    }
}
