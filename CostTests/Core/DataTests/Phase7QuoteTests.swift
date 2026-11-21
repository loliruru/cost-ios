import Foundation
import Testing
@testable import Cost

struct Phase7QuoteTests {
    private static let now: Int64 = 1_800_000_000_000
    private let usd = try! CurrencyCode("USD")
    private let cny = try! CurrencyCode("CNY")
    private let btc = try! CurrencyCode("BTC")

    @Test func retriesUseBoundedDelaysAndKeepRawDecimal() async throws {
        let transport = StubQuoteTransport([.response(429, "", retryAfter: "80"), .response(503, ""),
            .response(200, #"{"symbol":"USD/CNY","rate":7.123456789012345678,"timestamp":1799999999}"#)])
        let key = StubQuoteCredentials()
        let provider = provider(transport, credentials: key)
        let quote = try await provider.fiat(original: usd, base: cny, epochDay: nil)
        #expect(quote.rate.text == "7.123456789012345678")
        #expect(quote.expiresAt == 1_800_000_299_000)
        let trace = await transport.trace()
        #expect(trace.delays == [30_000, 500])
        #expect(trace.requests.count == 3)
        let request = try #require(trace.requests.last)
        let url = try #require(request.url)
        #expect(url.path == "/exchange_rate")
        #expect(url.query?.contains("dp=11") == true && url.query?.contains("timezone=UTC") == true)
        #expect(url.absoluteString.contains("fixture-key") == false)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "apikey fixture-key")
    }

    @Test func historicalRequiresReturnedUTCDayAndMarketUsesSeparateEndpoint() async throws {
        let transport = StubQuoteTransport([
            .response(200, #"{"symbol":"USD/CNY","rate":"7.1","timestamp":1799999999}"#),
            .response(200, #"{"symbol":"BTC/CNY","exchange":"Fixture","close":"421234.12345678901","timestamp":1799999999}"#)])
        let client = provider(transport, credentials: StubQuoteCredentials())
        let day = Self.now / 86_400_000 - 10
        await #expect(throws: QuoteFailure.noData) { try await client.fiat(original: usd, base: cny, epochDay: day) }
        let market = try await client.market(asset: btc, base: cny)
        #expect(market.price.text == "421234.12345678901" && market.venue == "Fixture")
        let requests = await transport.trace().requests
        #expect(requests[0].url?.query?.contains("T23:59:59") == true)
        #expect(requests[1].url?.path == "/quote" && requests[1].url?.query?.contains("interval=1min") == true)
    }

    @Test func missingKeyOfflineWrongPairAndMalformedTokenAreTyped() async throws {
        let transport = StubQuoteTransport([.failure(.notConnectedToInternet), .response(200, #"{"symbol":"CNY/USD","rate":7,"timestamp":1799999999}"#),
            .response(200, #"{"symbol":"USD/CNY","unused":{"rate":7},"rate":7e1,"timestamp":1799999999}"#)])
        let key = StubQuoteCredentials(key: nil)
        let client = provider(transport, credentials: key)
        await #expect(throws: QuoteFailure.notConfigured) { try await client.fiat(original: usd, base: cny, epochDay: nil) }
        #expect(await transport.trace().requests.isEmpty)
        await key.setAPIKey("fixture-key")
        await #expect(throws: QuoteFailure.offline) { try await client.fiat(original: usd, base: cny, epochDay: nil) }
        for _ in 0..<2 {
            await #expect(throws: QuoteFailure.malformedResponse) { try await client.fiat(original: usd, base: cny, epochDay: nil) }
        }
        #expect(await transport.trace().delays.isEmpty)
    }

    @Test func confirmationAndFreshnessUseProviderTimeAndKeepHistoricSnapshot() async throws {
        let db = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let transport = StubQuoteTransport([.response(404, ""),
            .response(200, #"{"symbol":"USD/CNY","rate":"7.125","timestamp":1799999700}"#),
            .response(200, #"{"symbol":"USD/CNY","rate":"7.5","timestamp":1799999999}"#)])
        let key = StubQuoteCredentials()
        let client = provider(transport, credentials: key)
        let quotes = QuoteServices(credentials: key, fiatProvider: client, marketProvider: client, fiatCache: db, marketCache: db, now: { Self.now })
        let past = try OccurredAt(epochMillis: Self.now - 86_400_000, zoneID: "Asia/Singapore")
        let offer = try await quotes.offer(original: usd, base: cny, type: .fiat, occurredAt: past)
        #expect(offer.snapshot.method == .currentFallback)
        #expect(offer.at(Self.now + 1).snapshot.method == .cachedFallback)
        let save = SaveEntryUseCase(transactions: db, currencies: db, environment: LedgerEnvironment(now: { Self.now }))
        var draft = EntryDraft(id: "fx-bill", requestKey: "fx-request", occurredMillis: past.epochMillis, zoneID: past.zoneID)
        draft.currencyCode = usd.rawValue
        draft.amount = "1.00"
        draft.categoryID = "seed-expense-other"
        draft.accountID = "seed-default-account"
        await #expect(throws: QuoteFailure.confirmationRequired) { try await save.save(draft, offer: offer) }
        let frozen = try await save.save(draft, offer: offer, confirmed: true)
        #expect(frozen.convertedBase.minorUnits == 712)
        let today = try OccurredAt(epochMillis: Self.now, zoneID: "Asia/Singapore")
        #expect(try await quotes.offer(original: usd, base: cny, type: .fiat, occurredAt: today, refresh: true).snapshot.rate.text == "7.5")
        draft.editingUpdatedAt = frozen.updatedAt
        draft.note = "仅修改备注"
        let edited = try await save.save(draft, existing: frozen)
        #expect(edited.convertedBase == frozen.convertedBase && edited.exchangeRate == frozen.exchangeRate)
        await key.setAPIKey(nil)
        await #expect(throws: QuoteFailure.notConfigured) { try await quotes.offer(original: usd, base: cny, type: .fiat, occurredAt: today) }
    }

    @Test func oneWaiterCanCancelWithoutInterruptingOtherCallers() async throws {
        let db = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let transport = StubQuoteTransport([.response(200, #"{"symbol":"USD/CNY","rate":"7","timestamp":1799999999}"#)], gated: true)
        let key = StubQuoteCredentials()
        let client = provider(transport, credentials: key)
        let quotes = QuoteServices(credentials: key, fiatProvider: client, marketProvider: client, fiatCache: db, marketCache: db, now: { Self.now })
        let first = Task { try await quotes.latest(original: usd, base: cny) }
        await transport.waitForStart()
        let second = Task { try await quotes.latest(original: usd, base: cny) }
        try await Task.sleep(for: .milliseconds(80))
        second.cancel()
        await #expect(throws: CancellationError.self) { try await second.value }
        await transport.release()
        #expect(try await first.value.rate.text == "7")
        #expect(await transport.trace().requests.count == 1)
    }

    @Test func cryptoMustBeEnabledAndActualSettlementOverridesAnInvalidManualPrice() async throws {
        let db = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        var draft = EntryDraft(id: "crypto-bill", requestKey: "crypto-request", occurredMillis: Self.now, zoneID: "UTC")
        draft.amount = "0.00000201"
        draft.currencyCode = btc.rawValue
        draft.accountID = "seed-default-account"
        draft.categoryID = "seed-expense-other"
        draft.actualBaseAmount = "8.77"
        draft.manualRate = "invalid"
        let save = SaveEntryUseCase(transactions: db, currencies: db, environment: LedgerEnvironment(now: { Self.now }))
        await #expect(throws: LedgerError.invalidCurrencyType) { try await save.save(draft) }
        var currency = try #require(try await db.currency(code: btc))
        currency.isEnabled = true
        try await db.saveCurrency(currency)
        let transaction = try await save.save(draft)
        #expect(transaction.original.scale == 8 && transaction.original.minorUnits == 201)
        #expect(transaction.convertedBase.minorUnits == 877)
        #expect(transaction.crypto?.pair == "BTC/CNY" && transaction.crypto?.kind == .actualSettlement)
        #expect(transaction.exchangeRate.method == .actualSettlement && transaction.exchangeRate.dataTimestamp == nil)
    }

    @Test func staleCryptoQuoteRequiresConfirmationAndNeverAppliesToAnEarlierDate() async throws {
        let db = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let transport = StubQuoteTransport([.response(200,
            #"{"symbol":"BTC/CNY","exchange":"Fixture","close":"400000.00000000001","timestamp":1799999699}"#)])
        let key = StubQuoteCredentials()
        let client = provider(transport, credentials: key)
        let quotes = QuoteServices(credentials: key, fiatProvider: client, marketProvider: client, fiatCache: db, marketCache: db, now: { Self.now })
        let today = try OccurredAt(epochMillis: Self.now, zoneID: "UTC")
        let yesterday = try OccurredAt(epochMillis: Self.now - 86_400_000, zoneID: "UTC")
        let offer = try await quotes.offer(original: btc, base: cny, type: .crypto, occurredAt: today)
        #expect(offer.requiresConfirmation && offer.snapshot.method == .cachedMarketPrice)
        let amount = try Money.parse("0.00000201", currencyCode: btc, scale: 8)
        #expect(throws: QuoteFailure.confirmationRequired) {
            try EntryValuation.resolve(original: amount, base: cny, scale: 2, type: .crypto, occurredAt: today, now: Self.now, offer: offer)
        }
        let result = try EntryValuation.resolve(original: amount, base: cny, scale: 2, type: .crypto, occurredAt: today,
            now: Self.now, offer: offer, confirmed: true)
        #expect(result.converted.minorUnits == 80 && result.crypto?.venue == "Fixture")
        await #expect(throws: QuoteFailure.cryptoHistorical) { try await quotes.offer(original: btc, base: cny, type: .crypto, occurredAt: yesterday) }
        #expect(await transport.trace().requests.count == 1)
    }

    @Test func foreignTemplateUsesLatestOnceAndAtomicallyRecordsUsage() async throws {
        let db = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let transport = StubQuoteTransport([.response(200,
            #"{"symbol":"USD/CNY","rate":"7.125","timestamp":1799999999}"#)])
        let key = StubQuoteCredentials()
        let client = provider(transport, credentials: key)
        let quotes = QuoteServices(credentials: key, fiatProvider: client, marketProvider: client, fiatCache: db, marketCache: db, now: { Self.now })
        let manage = ManageQuickTemplatesUseCase(templates: db, transactions: db, currencies: db,
            categories: db, accounts: db, tags: db, environment: LedgerEnvironment(now: { Self.now }, zoneID: { "UTC" }), quotes: quotes)
        var draft = QuickTemplateDraft()
        draft.name = "USD fixture"
        draft.currencyCode = "USD"
        draft.amount = "2.00"
        draft.categoryID = "seed-expense-other"
        draft.accountID = "seed-default-account"
        let template = try await manage.save(draft)
        let first = try await manage.record(templateID: template.id, requestID: "fixture-use")
        let replay = try await manage.record(templateID: template.id, requestID: "fixture-use")
        guard case .recorded(let transaction) = first, case .recorded(let repeated) = replay else {
            Issue.record("A fresh Fiat quote should record the template")
            return
        }
        #expect(transaction == repeated && transaction.convertedBase.minorUnits == 1425)
        #expect(transaction.exchangeRate.method == .latest)
        #expect(try await db.quickTemplate(id: template.id)?.usageCount == 1)
        #expect(await transport.trace().requests.count == 1)
    }

    private func provider(_ transport: StubQuoteTransport, credentials: StubQuoteCredentials) -> TwelveDataQuotes {
        TwelveDataQuotes(credentials: credentials, transport: transport, now: { Self.now }, delay: { await transport.logDelay($0) })
    }
}

private actor StubQuoteCredentials: QuoteCredentials {
    var key: String?
    init(key: String? = "fixture-key") { self.key = key }
    func apiKey() -> String? { key }
    func setAPIKey(_ key: String?) { self.key = key }
}

private actor StubQuoteTransport: QuoteHTTPTransport {
    enum Event: Sendable {
        case response(Int, String, retryAfter: String? = nil)
        case failure(URLError.Code)
    }
    private var events: [Event]
    private var requests: [URLRequest] = []
    private var delays: [Int64] = []
    private var gated: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var start: CheckedContinuation<Void, Never>?

    init(_ events: [Event], gated: Bool = false) {
        self.events = events
        self.gated = gated
    }

    func fetch(_ request: URLRequest) async throws -> QuoteHTTPResponse {
        requests.append(request)
        start?.resume()
        start = nil
        if gated { await withCheckedContinuation { waiters.append($0) } }
        try Task.checkCancellation()
        guard !events.isEmpty else { throw QuoteFailure.malformedResponse }
        switch events.removeFirst() {
        case .response(let status, let body, let retry): return QuoteHTTPResponse(status: status, retryAfter: retry, body: Data(body.utf8))
        case .failure(let code): throw URLError(code)
        }
    }

    func waitForStart() async {
        if requests.isEmpty { await withCheckedContinuation { start = $0 } }
    }

    func release() {
        gated = false
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func trace() -> (requests: [URLRequest], delays: [Int64]) { (requests, delays) }
    func logDelay(_ value: Int64) { delays.append(value) }
}
