import GRDB
import Testing
@testable import Cost

struct QuoteStorageTests {
    @Test
    func cacheRefreshAndCurrencyMetadataNeverRevalueHistory() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLedgerRepository(database: database)
        let usd = try CurrencyCode("USD"), cny = try CurrencyCode("CNY")
        let originalQuote = try FiatQuote(id: "quote", original: usd, base: cny, rate: DecimalRate("7.25"), providerID: "FIXTURE",
                                          dataTimestamp: 1000, rateEpochDay: nil, fetchedAt: 1001, expiresAt: 301000, kind: .latest)
        try await repository.saveFiatQuote(originalQuote)
        let transaction = try TestLedger.transaction(code: "USD", rate: "7.25", method: .latest)
        _ = try await repository.createTransaction(transaction)
        let changed = try FiatQuote(id: "quote", original: usd, base: cny, rate: DecimalRate("8.123456789012345678"), providerID: "FIXTURE",
                                    dataTimestamp: 2000, rateEpochDay: nil, fetchedAt: 2001, expiresAt: 302000, kind: .latest)
        try await repository.saveFiatQuote(changed)
        #expect(try await repository.latestFiatQuote(original: usd, base: cny, providerID: "FIXTURE") == changed)
        #expect(try await repository.latestFiatQuote(original: cny, base: usd, providerID: "FIXTURE") == nil)
        var currency = try #require(try await repository.currency(code: usd))
        currency.defaultScale = 4
        currency.symbol = "USD fixture"
        try await repository.saveCurrency(currency)
        #expect(try await repository.transaction(id: transaction.id) == transaction)
        try await database.writer.write { db in try db.execute(sql: "DELETE FROM fx_quotes") }
        #expect(try await repository.transaction(id: transaction.id) == transaction)
    }

    @Test
    func priceTextIsExactAndFiatAndCryptoCannotShareTheirCache() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let usd = try CurrencyCode("USD"), cny = try CurrencyCode("CNY"), btc = try CurrencyCode("BTC")
        let rate = try DecimalRate("99999999999999999999999999999999999999")
        let quote = FiatQuote(id: "precise", original: usd, base: cny, rate: rate, providerID: "FIXTURE",
                              dataTimestamp: 1000, rateEpochDay: nil, fetchedAt: 1001, expiresAt: 301000, kind: .latest)
        try await repository.saveFiatQuote(quote)
        #expect(try await repository.latestFiatQuote(original: usd, base: cny, providerID: "FIXTURE")?.rate.text == rate.text)
        let cryptoInFiat = FiatQuote(id: "wrong", original: btc, base: cny, rate: rate, providerID: "FIXTURE",
                                     dataTimestamp: 1000, rateEpochDay: nil, fetchedAt: 1001, expiresAt: 301000, kind: .latest)
        await #expect(throws: LedgerError.invalidCurrencyType) { try await repository.saveFiatQuote(cryptoInFiat) }
        let market = try MarketQuote(asset: btc, base: cny, providerID: "FIXTURE", price: DecimalRate("500000.123456789012345678"),
                                    venue: "fixture", dataTimestamp: 1000, fetchedAt: 1001, expiresAt: 301000)
        try await repository.saveMarketQuote(market)
        #expect(try await repository.marketQuote(asset: btc, base: cny, providerID: "FIXTURE") == market)
        #expect(try await repository.latestFiatQuote(original: usd, base: cny, providerID: "FIXTURE") == quote)
    }

    @Test
    func historicalQuoteUsesItsExplicitDateKey() async throws {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let usd = try CurrencyCode("USD"), cny = try CurrencyCode("CNY")
        let quote = try FiatQuote(id: "history", original: usd, base: cny, rate: DecimalRate("7.001"), providerID: "FIXTURE",
                                  dataTimestamp: 1000, rateEpochDay: 0, fetchedAt: 1001, expiresAt: 301000, kind: .historical)
        try await repository.saveFiatQuote(quote)
        #expect(try await repository.historicalFiatQuote(original: usd, base: cny, providerID: "FIXTURE", epochDay: 0) == quote)
        #expect(try await repository.historicalFiatQuote(original: usd, base: cny, providerID: "FIXTURE", epochDay: 1) == nil)
        #expect(try await repository.latestFiatQuote(original: usd, base: cny, providerID: "FIXTURE") == nil)
    }
}
