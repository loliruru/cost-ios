import Foundation

enum AccountAmountKind: String, CaseIterable, Sendable { case available = "AVAILABLE", investmentCost = "INVESTMENT_COST" }
enum FundsError: Error, Equatable, Sendable {
    case invalidAmount, overflow, accountUnavailable, currencyUnavailable, invalidProfit, categoryRequired
    case insufficientFunds, currencyMismatch, unvaluedTransactions
}

/// Exact signed derived total; unlike a persisted amount it may exceed Int64.
struct FundAmount: Equatable, Sendable {
    private(set) var magnitude: DecimalInteger
    private(set) var negative: Bool
    private(set) var scale: Int

    init(units: Int64, scale: Int) {
        let text = String(units)
        magnitude = DecimalInteger(text.hasPrefix("-") ? String(text.dropFirst()) : text)
        negative = units < 0
        self.scale = scale
    }
    var isNegative: Bool { negative && !magnitude.isZero }
    var text: String { (isNegative ? "-" : "") + PlainDecimal(coefficient: magnitude, scale: scale).text }

    mutating func add(units: Int64, scale otherScale: Int, subtract: Bool = false) {
        let other = FundAmount(units: units, scale: otherScale)
        let target = max(scale, otherScale)
        let left = magnitude.timesPowerOfTen(target - scale)
        let right = other.magnitude.timesPowerOfTen(target - otherScale)
        let rightNegative = other.negative != subtract
        if negative == rightNegative { magnitude = left.adding(right) }
        else if left >= right { magnitude = left.subtracting(right) }
        else { magnitude = right.subtracting(left); negative = rightNegative }
        scale = target
        if magnitude.isZero { negative = false }
    }

    static func parseMinor(_ input: String, scale: Int, signed: Bool = false) throws -> Int64 {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 96, (0...18).contains(scale) else { throw FundsError.invalidAmount }
        let negative = text.hasPrefix("-")
        guard signed || !negative else { throw FundsError.invalidAmount }
        let unsigned = negative ? String(text.dropFirst()) : text
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              parts.count == 1 || parts[1].count <= scale else { throw FundsError.invalidAmount }
        let value = try PlainDecimal(unsigned)
        let digits = value.coefficient.timesPowerOfTen(scale - value.scale).description
        guard let result = Int64((negative ? "-" : "") + digits) else { throw FundsError.overflow }
        return result
    }
}

struct AccountFundOpening: Equatable, Sendable {
    let id: String
    let accountID: String
    var revision: Int64 = 0
    let kind: AccountAmountKind
    let enabled: Bool
    let currencyCode: CurrencyCode
    let scale: Int
    let amountMinor: Int64?
    let startedAt: Int64
    let createdAt: Int64

    func validate() throws {
        try requireText(id, "openingID"); try requireText(accountID, "accountID")
        guard revision >= 0, (0...18).contains(scale), enabled ? (amountMinor.map { $0 >= 0 } ?? false) : amountMinor == nil
        else { throw FundsError.invalidAmount }
    }
    func includes(occurred: Int64, created: Int64) -> Bool {
        occurred > startedAt || (occurred == startedAt && created > createdAt)
    }
}

struct AccountTransfer: Equatable, Sendable {
    let id: String
    let requestKey: String
    let fromAccountID: String
    let toAccountID: String
    let fromKind: AccountAmountKind
    let toKind: AccountAmountKind
    let currencyCode: CurrencyCode
    let scale: Int
    let principalMinor: Int64
    let profitMinor: Int64
    let profitCategoryID: String?
    var profitTransactionID: String?
    let occurredAt: OccurredAt
    let note: String?
    let createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64? = nil

    func validate() throws {
        try requireText(id, "transferID"); try requireText(requestKey, "requestKey")
        try requireText(fromAccountID, "fromAccountID"); try requireText(toAccountID, "toAccountID")
        let received = principalMinor.addingReportingOverflow(profitMinor)
        guard !received.overflow else { throw FundsError.overflow }
        guard fromAccountID != toAccountID, (0...18).contains(scale), principalMinor >= 0,
              received.partialValue >= 0, principalMinor > 0 || profitMinor > 0, profitMinor != .min,
              profitMinor == 0 || (fromKind == .investmentCost && toKind == .available),
              profitMinor == 0 ? profitCategoryID == nil : !(profitCategoryID?.isEmpty ?? true)
        else { throw FundsError.invalidProfit }
        try requireTimes(created: createdAt, updated: updatedAt, deleted: deletedAt)
    }

    func samePayload(as other: Self) -> Bool {
        fromAccountID == other.fromAccountID && toAccountID == other.toAccountID && fromKind == other.fromKind && toKind == other.toKind &&
        currencyCode == other.currencyCode && scale == other.scale && principalMinor == other.principalMinor && profitMinor == other.profitMinor &&
        profitCategoryID == other.profitCategoryID && occurredAt == other.occurredAt && note == other.note
    }

    func profitTransaction(existing: LedgerTransaction?) throws -> LedgerTransaction {
        guard profitMinor != 0, profitMinor != .min, let category = profitCategoryID else { throw FundsError.invalidProfit }
        let money = try Money(minorUnits: abs(profitMinor), currencyCode: currencyCode, scale: scale)
        return try LedgerTransaction(id: existing?.id ?? "account-pnl-\(id)", type: profitMinor > 0 ? .income : .expense,
            original: money, convertedBase: money,
            exchangeRate: ExchangeRateSnapshot(rate: DecimalRate("1"), providerID: "IDENTITY", dataTimestamp: nil, fetchedAt: nil, method: .identity),
            categoryID: category, accountID: toAccountID, occurredAt: occurredAt,
            note: note ?? (profitMinor > 0 ? "投资收益" : "投资亏损"), requestKey: "account-transfer-pnl:\(id)",
            createdAt: existing?.createdAt ?? updatedAt, updatedAt: max(updatedAt, existing?.updatedAt ?? updatedAt), deletedAt: deletedAt)
    }
}

struct AccountPosition: Equatable, Sendable {
    let accountID: String
    let opening: AccountFundOpening?
    let amount: FundAmount?
    let unvaluedCount: Int
}

enum AccountFundsCalculator {
    static func position(accountID: String, opening: AccountFundOpening?, transactions: [LedgerTransaction], transfers: [AccountTransfer]) -> AccountPosition {
        guard let opening, opening.enabled, let units = opening.amountMinor else {
            return AccountPosition(accountID: accountID, opening: opening, amount: nil, unvaluedCount: 0)
        }
        var total = FundAmount(units: units, scale: opening.scale)
        var missing = 0
        if opening.kind == .available {
            for row in transactions where row.accountID == accountID && row.deletedAt == nil && opening.includes(occurred: row.occurredAt.epochMillis, created: row.createdAt) {
                let money = row.original.currencyCode == opening.currencyCode ? row.original :
                    (row.convertedBase.currencyCode == opening.currencyCode ? row.convertedBase : nil)
                if let money { total.add(units: money.minorUnits, scale: money.scale, subtract: row.type == .expense) }
                else { missing += 1 }
            }
        }
        for row in transfers where row.deletedAt == nil && (row.fromAccountID == accountID || row.toAccountID == accountID) && opening.includes(occurred: row.occurredAt.epochMillis, created: row.createdAt) {
            if row.currencyCode != opening.currencyCode { missing += 1; continue }
            total.add(units: row.principalMinor, scale: row.scale, subtract: row.fromAccountID == accountID)
        }
        return AccountPosition(accountID: accountID, opening: opening, amount: total, unvaluedCount: missing)
    }
}
