import Foundation

struct LedgerCursor: Equatable, Sendable { let occurredAt: Int64; let id: String }
struct LedgerQuery: Equatable, Sendable {
    var text = ""
    var type: TransactionType?
    var categoryID: String?
    var accountID: String?
    var tagID: String?
    var startDay: Int64?
    var endDayExclusive: Int64?
    var deletedOnly = false
    var cursor: LedgerCursor?
    var limit = 200
}
struct LedgerPage: Sendable { let rows: [LedgerTransaction]; let next: LedgerCursor? }

struct EntryDraft: Codable, Equatable, Sendable {
    var id: String
    var requestKey: String
    var amount = ""
    var typeRaw = TransactionType.expense.rawValue
    var categoryID = ""
    var accountID = ""
    var currencyCode = "CNY"
    var baseCurrencyCode = "CNY"
    var baseScale = 2
    var occurredMillis: Int64
    var zoneID: String
    var note = ""
    var tagIDs: Set<String> = []
    var editingUpdatedAt: Int64?
    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }
}

struct LedgerEnvironment: Sendable {
    var now: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    var newID: @Sendable () -> String = { UUID().uuidString.lowercased() }
    var zoneID: @Sendable () -> String = { TimeZone.current.identifier }

    func timestamp(after previous: Int64?) throws -> Int64 {
        guard let previous else { return now() }
        let next = previous.addingReportingOverflow(1)
        guard !next.overflow else { throw LedgerError.dateOverflow }
        return max(now(), next.partialValue)
    }
}

struct SaveEntryUseCase: Sendable {
    let transactions: any TransactionRepository
    let currencies: any CurrencyRepository
    var environment = LedgerEnvironment()

    func save(_ draft: EntryDraft, existing: LedgerTransaction? = nil) async throws -> LedgerTransaction {
        guard draft.amount.count <= 96, draft.note.count <= 8192, draft.tagIDs.count <= 100 else { throw LedgerError.invalidField("inputLimit") }
        if let existing, draft.editingUpdatedAt != existing.updatedAt { throw LedgerError.conflict }
        let code = try CurrencyCode(draft.currencyCode)
        guard let currency = try await currencies.currency(code: code), currency.assetType == .fiat,
              currency.isEnabled || existing?.original.currencyCode == code else { throw LedgerError.invalidCurrencyType }
        guard code.rawValue == draft.baseCurrencyCode else { throw LedgerError.invalidSnapshot }
        let scale = existing?.original.currencyCode == code ? existing!.original.scale : draft.baseScale
        let money = try Money.parse(draft.amount, currencyCode: code, scale: scale)
        let timestamp = try environment.timestamp(after: existing?.updatedAt)
        let row = try LedgerTransaction(id: existing?.id ?? draft.id, type: draft.type,
            original: money, convertedBase: money,
            exchangeRate: ExchangeRateSnapshot(rate: DecimalRate("1"), providerID: "IDENTITY", dataTimestamp: nil, fetchedAt: nil, method: .identity),
            categoryID: draft.categoryID, accountID: draft.accountID,
            occurredAt: OccurredAt(epochMillis: draft.occurredMillis, zoneID: draft.zoneID),
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            source: existing?.source ?? .manual, sourceID: existing?.sourceID,
            requestKey: existing == nil ? draft.requestKey : existing!.requestKey, createdAt: existing?.createdAt ?? timestamp,
            updatedAt: timestamp, tagIDs: draft.tagIDs)
        if let existing {
            guard existing.deletedAt == nil, try await transactions.updateTransaction(row, expectedUpdatedAt: existing.updatedAt) else { throw LedgerError.conflict }
            return row
        }
        return try await transactions.createTransaction(row)
    }
}

struct ManageFundsUseCase: Sendable {
    let repository: any AccountFundsRepository
    let currencies: any CurrencyRepository
    var environment = LedgerEnvironment()

    func setOpening(accountID: String, kind: AccountAmountKind, enabled: Bool, code: String, amount: String) async throws {
        guard let currency = try await currencies.currency(code: CurrencyCode(code)), currency.isEnabled, currency.assetType == .fiat else { throw FundsError.currencyUnavailable }
        let timestamp = environment.now()
        let opening = AccountFundOpening(id: environment.newID(), accountID: accountID, kind: kind, enabled: enabled,
            currencyCode: currency.code, scale: currency.defaultScale,
            amountMinor: enabled ? try FundAmount.parseMinor(amount, scale: currency.defaultScale) : nil,
            startedAt: timestamp, createdAt: timestamp)
        _ = try await repository.saveOpening(opening)
    }

    func saveTransfer(id: String, requestKey: String, from: String, to: String, code: String, principal: String,
                      profit: String, categoryID: String?, occurredAt: OccurredAt, note: String, existing: AccountTransfer?) async throws -> AccountTransfer {
        guard let currency = try await currencies.currency(code: CurrencyCode(code)), currency.isEnabled, currency.assetType == .fiat else { throw FundsError.currencyUnavailable }
        let scale = existing?.currencyCode == currency.code ? existing!.scale : currency.defaultScale
        let fromOpening = try await repository.latestOpening(accountID: from)
        let toOpening = try await repository.latestOpening(accountID: to)
        let fromKind = existing.flatMap { from == $0.fromAccountID ? $0.fromKind : (from == $0.toAccountID ? $0.toKind : nil) } ?? fromOpening?.kind ?? .available
        let toKind = existing.flatMap { to == $0.fromAccountID ? $0.fromKind : (to == $0.toAccountID ? $0.toKind : nil) } ?? toOpening?.kind ?? .available
        let profitUnits = try FundAmount.parseMinor(profit.isEmpty ? "0" : profit, scale: scale, signed: true)
        let timestamp = try environment.timestamp(after: existing?.updatedAt)
        let row = AccountTransfer(id: existing?.id ?? id, requestKey: existing?.requestKey ?? requestKey,
            fromAccountID: from, toAccountID: to, fromKind: fromKind, toKind: toKind, currencyCode: currency.code,
            scale: scale, principalMinor: try FundAmount.parseMinor(principal, scale: scale), profitMinor: profitUnits,
            profitCategoryID: profitUnits == 0 ? nil : categoryID, profitTransactionID: existing?.profitTransactionID,
            occurredAt: occurredAt, note: note.isEmpty ? nil : note, createdAt: existing?.createdAt ?? timestamp, updatedAt: timestamp)
        return try await repository.saveTransfer(row, expectedUpdatedAt: existing?.updatedAt)
    }
}
