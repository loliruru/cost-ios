import Foundation
import Observation

@MainActor @Observable
final class QuickTemplatesViewModel {
    let ledger: LedgerViewModel
    private(set) var rows: [QuickTemplate] = []
    private(set) var isBusy = false
    var error: String?
    private(set) var notice: String?
    private(set) var recorded: LedgerTransaction?
    @ObservationIgnored private var pendingRequests: [String: String] = [:]
    @ObservationIgnored private var recentTap: (id: String, expires: ContinuousClock.Instant)?
    @ObservationIgnored private var loadGeneration = 0

    init(ledger: LedgerViewModel) { self.ledger = ledger }

    private var useCase: ManageQuickTemplatesUseCase {
        let services = ledger.services
        return ManageQuickTemplatesUseCase(templates: services.templates, transactions: services.transactions,
            currencies: services.currencies, categories: services.categories, accounts: services.accounts,
            tags: services.tags, environment: ledger.environment)
    }

    func reload() async {
        loadGeneration += 1
        let token = loadGeneration
        do {
            let loaded = try await ledger.services.templates.quickTemplates()
            if token == loadGeneration && !Task.isCancelled { rows = loaded }
        } catch is CancellationError {
        } catch {
            if token == loadGeneration { self.error = LedgerMessage.text(error) }
        }
    }

    func record(_ template: QuickTemplate) async -> EntryDraft? {
        guard !isBusy else { return nil }
        let now = ContinuousClock.now
        if let recentTap, recentTap.id == template.id && now < recentTap.expires { return nil }
        recentTap = (template.id, now.advanced(by: .milliseconds(600)))
        isBusy = true
        defer { isBusy = false }
        let requestID = pendingRequests[template.id] ?? ledger.environment.newID()
        pendingRequests[template.id] = requestID
        do {
            let result = try await useCase.record(templateID: template.id, requestID: requestID)
            pendingRequests.removeValue(forKey: template.id)
            switch result {
            case .recorded(let transaction):
                recorded = transaction.deletedAt == nil ? transaction : nil
                notice = transaction.deletedAt == nil ? "已记账" : "这次记账已撤销"
                await reload()
                await ledger.reload()
                return nil
            case .needsValuation(let draft):
                return draft
            }
        } catch {
            self.error = LedgerMessage.text(error)
            return nil
        }
    }

    func entryDraft(for template: QuickTemplate) async -> EntryDraft? {
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        do { return try await useCase.entryDraft(templateID: template.id) }
        catch { self.error = LedgerMessage.text(error); return nil }
    }

    func undo() async {
        guard !isBusy, let recorded else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let timestamp = try ledger.environment.timestamp(after: recorded.updatedAt)
            guard try await ledger.services.transactions.softDeleteTransaction(id: recorded.id, at: timestamp) else {
                throw LedgerError.conflict
            }
            self.recorded = nil
            notice = "已撤销记账"
            await reload()
            await ledger.reload()
        } catch { self.error = LedgerMessage.text(error) }
    }

    func save(_ draft: QuickTemplateDraft, editing existing: QuickTemplate?) async throws {
        _ = try await useCase.save(draft, editing: existing)
        await reload()
    }

    func setArchived(_ archived: Bool, template: QuickTemplate) async throws {
        try await ledger.services.templates.setQuickTemplateArchived(id: template.id, archived: archived,
            expectedUpdatedAt: template.updatedAt, at: ledger.environment.now())
        await reload()
    }

    func delete(_ template: QuickTemplate) async throws {
        try await ledger.services.templates.deleteQuickTemplate(id: template.id, expectedUpdatedAt: template.updatedAt)
        await reload()
    }
}

@MainActor @Observable
final class QuickTemplateEditorModel {
    let templates: QuickTemplatesViewModel
    let existing: QuickTemplate?
    var draft = QuickTemplateDraft()
    var order = ""
    var error: String?
    private(set) var isBusy = false

    init(templates: QuickTemplatesViewModel, existing: QuickTemplate?) {
        self.templates = templates
        self.existing = existing
        let ledger = templates.ledger
        draft.accountID = ledger.accounts.first { $0.isDefault && !$0.isArchived }?.id ?? ledger.accounts.first { !$0.isArchived }?.id ?? ""
        draft.categoryID = ledger.categories.first { !$0.isArchived && $0.type == .expense }?.id ?? ""
        if let existing {
            let value = existing.content
            draft = QuickTemplateDraft(name: value.name, iconKey: value.iconKey, type: value.type,
                amount: value.amount.plainText, currencyCode: value.amount.currencyCode.rawValue,
                categoryID: value.categoryID, accountID: value.accountID, note: value.note ?? "", tagIDs: value.tagIDs)
            order = String(existing.sortOrder)
        }
    }

    func selectCategory(for type: TransactionType) {
        let options = templates.ledger.categories.filter { $0.type == type && !$0.isArchived }
        if !options.contains(where: { $0.id == draft.categoryID }) {
            draft.categoryID = options.first?.id ?? ""
        }
    }

    func save() async -> Bool {
        await perform {
            let input = order.trimmingCharacters(in: .whitespacesAndNewlines)
            if !input.isEmpty, Int64(input) == nil { throw LedgerError.invalidField("templateOrder") }
            var value = draft
            value.sortOrder = Int64(input)
            try await templates.save(value, editing: existing)
        }
    }

    func setArchived() async -> Bool {
        guard let existing else { return false }
        return await perform { try await templates.setArchived(!existing.isArchived, template: existing) }
    }

    func delete() async -> Bool {
        guard let existing else { return false }
        return await perform { try await templates.delete(existing) }
    }

    private func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do { try await operation(); return true }
        catch { self.error = LedgerMessage.text(error); return false }
    }
}
