import Foundation

struct QuickTemplateContent: Equatable, Sendable {
    var name: String
    var iconKey: String
    var type: TransactionType
    var amount: Money
    var categoryID: String
    var accountID: String
    var note: String?
    var tagIDs: Set<String>
}

struct QuickTemplate: Equatable, Identifiable, Sendable {
    let id: String
    let content: QuickTemplateContent
    let sortOrder: Int64
    let usageCount: Int64
    let lastUsedAt: Int64?
    let isArchived: Bool
    let createdAt: Int64
    let updatedAt: Int64
}

struct QuickTemplateDraft: Sendable {
    var name = ""
    var iconKey = "receipt"
    var type = TransactionType.expense
    var amount = ""
    var currencyCode = "CNY"
    var categoryID = ""
    var accountID = ""
    var note = ""
    var tagIDs: Set<String> = []
    var sortOrder: Int64?
}

enum QuickTemplateError: Error, Equatable, Sendable {
    case unavailable, categoryUnavailable, accountUnavailable, tagUnavailable, currencyUnavailable, usageOverflow
}

protocol QuickTemplateRepository: Sendable {
    func quickTemplates() async throws -> [QuickTemplate]
    func quickTemplate(id: String) async throws -> QuickTemplate?
    func saveQuickTemplate(id: String, content: QuickTemplateContent, sortOrder: Int64?, expectedUpdatedAt: Int64?, at: Int64) async throws -> QuickTemplate
    func setQuickTemplateArchived(id: String, archived: Bool, expectedUpdatedAt: Int64, at: Int64) async throws
    func deleteQuickTemplate(id: String, expectedUpdatedAt: Int64) async throws
    func recordQuickTemplateUse(_ transaction: LedgerTransaction, expecting: QuickTemplateContent) async throws -> LedgerTransaction
}

enum QuickTemplateUse {
    static let requestPrefix = "quick-template-use:"

    static func recordsUsage(source: TransactionSource, requestKey: String?) -> Bool {
        source == .template && requestKey?.hasPrefix(requestPrefix) == true
    }
}

enum QuickTemplateAction: Sendable {
    case recorded(LedgerTransaction)
    case needsValuation(EntryDraft)
}

struct ManageQuickTemplatesUseCase: Sendable {
    let templates: any QuickTemplateRepository
    let transactions: any TransactionRepository
    let currencies: any CurrencyRepository
    let categories: any CategoryRepository
    let accounts: any AccountRepository
    let tags: any TagRepository
    var environment = LedgerEnvironment()
    var quotes: QuoteServices? = nil
    var basePreferences: (any BaseCurrencyPreferences)? = nil

    func save(_ draft: QuickTemplateDraft, editing existing: QuickTemplate? = nil) async throws -> QuickTemplate {
        let name = draft.name.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let icon = draft.iconKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120, !icon.isEmpty, icon.count <= 64,
              draft.amount.count <= 96, draft.note.count <= 8192, draft.tagIDs.count <= 100 else {
            throw LedgerError.invalidField("templateInput")
        }
        let code = try CurrencyCode(draft.currencyCode)
        guard let currency = try await currencies.currency(code: code), currency.assetType == .fiat,
              currency.isEnabled || existing?.content.amount.currencyCode == code else {
            throw QuickTemplateError.currencyUnavailable
        }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = QuickTemplateContent(name: name, iconKey: icon, type: draft.type,
            amount: try Money.parse(draft.amount, currencyCode: code, scale: currency.defaultScale),
            categoryID: draft.categoryID, accountID: draft.accountID, note: note.isEmpty ? nil : note, tagIDs: draft.tagIDs)
        return try await templates.saveQuickTemplate(id: existing?.id ?? environment.newID(), content: content,
            sortOrder: draft.sortOrder, expectedUpdatedAt: existing?.updatedAt, at: environment.timestamp(after: existing?.updatedAt))
    }

    func entryDraft(templateID: String) async throws -> EntryDraft {
        let template = try await availableTemplate(id: templateID)
        return try await prefill(template)
    }

    func record(templateID: String, requestID: String) async throws -> QuickTemplateAction {
        try requireText(requestID, "templateRequestID")
        let requestKey = QuickTemplateUse.requestPrefix + requestID
        if let prior = try await transactions.transaction(requestKey: requestKey) {
            guard prior.source == .template, prior.sourceID == templateID else { throw LedgerError.conflict }
            return .recorded(prior)
        }
        let template = try await availableTemplate(id: templateID)
        let draft = try await prefill(template)
        let content = template.content
        let base = try CurrencyCode(draft.baseCurrencyCode)
        let occurred = try OccurredAt(epochMillis: draft.occurredMillis, zoneID: draft.zoneID)
        let money: Money
        let valuation: EntryValuation
        if content.amount.currencyCode == base {
            money = try content.amount.rescaled(to: draft.baseScale)
            valuation = try EntryValuation.resolve(original: money, base: base, scale: draft.baseScale, type: .fiat,
                occurredAt: occurred, now: environment.now())
        } else {
            guard let quotes else { return .needsValuation(draft) }
            money = content.amount
            do {
                let offer = try await quotes.offer(original: money.currencyCode, base: base, type: .fiat, occurredAt: occurred)
                if offer.requiresConfirmation { return .needsValuation(draft) }
                valuation = try EntryValuation.resolve(original: money, base: base, scale: draft.baseScale, type: .fiat,
                    occurredAt: occurred, now: environment.now(), offer: offer)
            } catch is QuoteFailure { return .needsValuation(draft) }
        }
        try Task.checkCancellation()
        let timestamp = max(draft.occurredMillis, template.createdAt)
        let transaction = try LedgerTransaction(id: draft.id, type: content.type, original: money,
            convertedBase: valuation.converted, exchangeRate: valuation.rate, categoryID: content.categoryID, accountID: content.accountID,
            occurredAt: occurred, note: content.note,
            source: .template, sourceID: template.id, requestKey: requestKey, createdAt: timestamp, updatedAt: timestamp, tagIDs: content.tagIDs)
        return .recorded(try await templates.recordQuickTemplateUse(transaction, expecting: content))
    }

    private func availableTemplate(id: String) async throws -> QuickTemplate {
        guard let template = try await templates.quickTemplate(id: id), !template.isArchived else { throw QuickTemplateError.unavailable }
        let content = template.content
        guard let currency = try await currencies.currency(code: content.amount.currencyCode),
              currency.isEnabled, currency.assetType == .fiat else { throw QuickTemplateError.currencyUnavailable }
        guard let category = try await categories.category(id: content.categoryID),
              !category.isArchived, category.type == content.type else { throw QuickTemplateError.categoryUnavailable }
        guard let account = try await accounts.account(id: content.accountID), !account.isArchived else { throw QuickTemplateError.accountUnavailable }
        for id in content.tagIDs {
            guard let tag = try await tags.tag(id: id), !tag.isArchived else { throw QuickTemplateError.tagUnavailable }
        }
        return template
    }

    private func prefill(_ template: QuickTemplate) async throws -> EntryDraft {
        let base = try await preferredBaseCurrency(basePreferences, in: currencies)
        let content = template.content
        var draft = EntryDraft(id: environment.newID(), requestKey: environment.newID(),
            occurredMillis: environment.now(), zoneID: environment.zoneID())
        draft.sourceTemplateID = template.id
        draft.amount = content.amount.plainText
        draft.type = content.type
        draft.categoryID = content.categoryID
        draft.accountID = content.accountID
        draft.currencyCode = content.amount.currencyCode.rawValue
        draft.baseCurrencyCode = base.code.rawValue
        draft.baseScale = base.defaultScale
        draft.note = content.note ?? ""
        draft.tagIDs = content.tagIDs
        return draft
    }
}
