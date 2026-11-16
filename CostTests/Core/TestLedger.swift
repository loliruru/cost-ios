import Foundation
@testable import Cost

enum TestLedger {
    static func transaction(id: String = "test-transaction", units: Int64 = 1234, code: String = "CNY", scale: Int = 2,
                            rate: String = "1", baseUnits: Int64? = nil, method: ValuationMethod = .identity,
                            category: String = "seed-expense-other", account: String = "seed-default-account",
                            type: TransactionType = .expense, occurred: Int64 = 86_400_000,
                            source: TransactionSource = .manual, sourceID: String? = nil, requestKey: String? = nil,
                            created: Int64 = 10, updated: Int64 = 10, deleted: Int64? = nil,
                            tags: Set<String> = [], note: String? = "fixture", crypto: CryptoValuationSnapshot? = nil) throws -> LedgerTransaction {
        let original = try Money(minorUnits: units, currencyCode: CurrencyCode(code), scale: scale)
        let exchange = try DecimalRate(rate)
        let base = try Money(minorUnits: baseUnits ?? exchange.convert(original, to: CurrencyCode("CNY"), scale: 2).minorUnits,
                             currencyCode: CurrencyCode("CNY"), scale: 2)
        let provider = method == .identity ? "IDENTITY" : (method == .actualSettlement ? "ACTUAL_SETTLEMENT" : "FIXTURE")
        return try LedgerTransaction(id: id, type: type, original: original, convertedBase: base,
            exchangeRate: ExchangeRateSnapshot(rate: exchange, providerID: provider,
                dataTimestamp: method.isProviderBacked ? 1000 : nil, fetchedAt: method.isProviderBacked ? 1001 : nil, method: method),
            categoryID: category, accountID: account, occurredAt: OccurredAt(epochMillis: occurred, zoneID: "UTC"),
            note: note, source: source, sourceID: sourceID, requestKey: requestKey, createdAt: created, updatedAt: updated,
            deletedAt: deleted, tagIDs: tags, crypto: crypto)
    }

    static func tag(id: String = "test-tag", name: String = "测试标签", archived: Bool = false, updated: Int64 = 10) -> Tag {
        Tag(id: id, name: name, isArchived: archived, createdAt: 10, updatedAt: updated)
    }
}
