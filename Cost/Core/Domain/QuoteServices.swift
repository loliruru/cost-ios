import Foundation

enum QuoteFailure: Error, Equatable, Sendable {
    case notConfigured, credentialsUnavailable, unauthorized, invalidRequest, noData
    case offline, timeout, rateLimited, unavailable, malformedResponse, confirmationRequired
    case cryptoHistorical, futureDate
}

protocol QuoteCredentials: Sendable {
    func apiKey() async throws -> String?
    func setAPIKey(_ key: String?) async throws
}

protocol FiatRateProvider: Sendable {
    var fiatProviderID: String { get }
    func fiat(original: CurrencyCode, base: CurrencyCode, epochDay: Int64?) async throws -> FiatQuote
}

protocol MarketPriceProvider: Sendable {
    var marketProviderID: String { get }
    func market(asset: CurrencyCode, base: CurrencyCode) async throws -> MarketQuote
}

enum QuoteFreshness {
    static let lifetime: Int64 = 300_000

    static func isFresh(data: Int64, expiry: Int64, now: Int64) -> Bool {
        data > 0 && data <= now && now <= expiry && now - data <= lifetime
    }

    static func isFresh(_ quote: FiatQuote, now: Int64) -> Bool {
        isFresh(data: quote.dataTimestamp, expiry: quote.expiresAt, now: now)
    }

    static func isFresh(_ quote: MarketQuote, now: Int64) -> Bool {
        isFresh(data: quote.dataTimestamp, expiry: quote.expiresAt, now: now) &&
            isFresh(data: quote.fetchedAt, expiry: quote.expiresAt, now: now)
    }
}

struct ValuationOffer: Equatable, Sendable {
    let original: CurrencyCode
    let base: CurrencyCode
    let day: Int64
    let zoneID: String
    private(set) var snapshot: ExchangeRateSnapshot
    var venue: String? = nil
    var requiresConfirmation: Bool {
        [.cachedFallback, .currentFallback, .cachedMarketPrice].contains(snapshot.method)
    }

    func at(_ now: Int64) -> Self {
        guard [.latest, .currentFallback, .marketPrice].contains(snapshot.method),
              let data = snapshot.dataTimestamp, let fetched = snapshot.fetchedAt,
              !QuoteFreshness.isFresh(data: data, expiry: .max, now: now) ||
                (venue != nil && !QuoteFreshness.isFresh(data: fetched, expiry: .max, now: now)) else { return self }
        var updated = self
        updated.snapshot = ExchangeRateSnapshot(rate: snapshot.rate, providerID: snapshot.providerID,
            dataTimestamp: data, fetchedAt: fetched, method: venue == nil ? .cachedFallback : .cachedMarketPrice)
        return updated
    }

    init(_ quote: FiatQuote, method: ValuationMethod, occurredAt: OccurredAt) {
        original = quote.original
        base = quote.base
        day = occurredAt.localEpochDay
        zoneID = occurredAt.zoneID
        snapshot = ExchangeRateSnapshot(rate: quote.rate, providerID: quote.providerID,
            dataTimestamp: quote.dataTimestamp, fetchedAt: quote.fetchedAt, method: method)
    }

    init(_ quote: MarketQuote, method: ValuationMethod, occurredAt: OccurredAt) {
        original = quote.asset
        base = quote.base
        day = occurredAt.localEpochDay
        zoneID = occurredAt.zoneID
        venue = quote.venue
        snapshot = ExchangeRateSnapshot(rate: quote.price, providerID: quote.providerID,
            dataTimestamp: quote.dataTimestamp, fetchedAt: quote.fetchedAt, method: method)
    }
}

struct QuoteServices: RecurringFiatProvider {
    let credentials: any QuoteCredentials
    let fiatProvider: any FiatRateProvider
    let marketProvider: any MarketPriceProvider
    let fiatCache: any FiatQuoteRepository
    let marketCache: any MarketQuoteRepository
    var now: @Sendable () -> Int64
    private let fiatRequests = SharedQuoteRequests<FiatKey, FiatQuote>()
    private let marketRequests = SharedQuoteRequests<Pair, MarketQuote>()

    init(credentials: any QuoteCredentials, fiatProvider: any FiatRateProvider, marketProvider: any MarketPriceProvider,
         fiatCache: any FiatQuoteRepository, marketCache: any MarketQuoteRepository, now: @escaping @Sendable () -> Int64) {
        self.credentials = credentials
        self.fiatProvider = fiatProvider
        self.marketProvider = marketProvider
        self.fiatCache = fiatCache
        self.marketCache = marketCache
        self.now = now
    }

    private struct Pair: Hashable, Sendable {
        let original: CurrencyCode
        let base: CurrencyCode
    }

    private struct FiatKey: Hashable, Sendable {
        let pair: Pair
        let epochDay: Int64?
    }

    func latest(original: CurrencyCode, base: CurrencyCode) async throws -> FiatQuote {
        try await fiat(original: original, base: base, epochDay: nil)
    }

    func historical(original: CurrencyCode, base: CurrencyCode, epochDay: Int64) async throws -> FiatQuote {
        try await fiat(original: original, base: base, epochDay: epochDay)
    }

    private func fiat(original: CurrencyCode, base: CurrencyCode, epochDay: Int64?, refresh: Bool = false) async throws -> FiatQuote {
        let key = FiatKey(pair: Pair(original: original, base: base), epochDay: epochDay)
        return try await fiatRequests.value(for: key) {
            try await requireCredentials()
            let providerID = fiatProvider.fiatProviderID
            let cached: FiatQuote?
            if let epochDay {
                cached = try await fiatCache.historicalFiatQuote(original: original, base: base, providerID: providerID, epochDay: epochDay)
                if let cached, try OccurredAt(epochMillis: cached.dataTimestamp, zoneID: "UTC").localEpochDay == epochDay { return cached }
            } else {
                cached = try await cachedFiat(original: original, base: base)
                if !refresh, let cached, QuoteFreshness.isFresh(cached, now: now()) { return cached }
            }
            let quote = try await fiatProvider.fiat(original: original, base: base, epochDay: epochDay)
            try Task.checkCancellation()
            guard quote.original == original, quote.base == base, quote.providerID == providerID,
                  quote.kind == (epochDay == nil ? .latest : .historical), quote.rateEpochDay == epochDay else {
                throw QuoteFailure.malformedResponse
            }
            if let epochDay, try OccurredAt(epochMillis: quote.dataTimestamp, zoneID: "UTC").localEpochDay != epochDay {
                throw QuoteFailure.noData
            }
            if epochDay == nil, let cached, cached.dataTimestamp >= quote.dataTimestamp,
               cached.dataTimestamp <= now(), cached.fetchedAt <= now() { return cached }
            try await fiatCache.saveFiatQuote(quote)
            return quote
        }
    }

    func offer(original: CurrencyCode, base: CurrencyCode, type: AssetType, occurredAt: OccurredAt, refresh: Bool = false) async throws -> ValuationOffer {
        let today = try OccurredAt(epochMillis: now(), zoneID: occurredAt.zoneID).localEpochDay
        guard occurredAt.localEpochDay <= today else { throw QuoteFailure.futureDate }
        try await requireCredentials()
        if type == .crypto {
            guard occurredAt.localEpochDay == today else { throw QuoteFailure.cryptoHistorical }
            let quote = try await market(original: original, base: base, refresh: refresh)
            return ValuationOffer(quote, method: QuoteFreshness.isFresh(quote, now: now()) ? .marketPrice : .cachedMarketPrice, occurredAt: occurredAt)
        }
        let past = occurredAt.localEpochDay < today
        if past {
            do {
                return ValuationOffer(try await historical(original: original, base: base, epochDay: occurredAt.localEpochDay),
                    method: .historical, occurredAt: occurredAt)
            } catch let failure as QuoteFailure where failure.permitsFallback { }
        }
        let quote: FiatQuote
        do { quote = try await fiat(original: original, base: base, epochDay: nil, refresh: refresh) }
        catch let failure as QuoteFailure where failure.permitsFallback {
            guard let cached = try await cachedFiat(original: original, base: base) else { throw failure }
            quote = cached
        }
        let instant = now()
        guard quote.dataTimestamp <= instant, quote.fetchedAt <= instant else { throw QuoteFailure.malformedResponse }
        return ValuationOffer(quote, method: QuoteFreshness.isFresh(quote, now: instant)
            ? (past ? .currentFallback : .latest) : .cachedFallback, occurredAt: occurredAt)
    }

    private func market(original: CurrencyCode, base: CurrencyCode, refresh: Bool) async throws -> MarketQuote {
        try await marketRequests.value(for: Pair(original: original, base: base)) {
            try await requireCredentials()
            let providerID = marketProvider.marketProviderID
            let cached = try await marketCache.marketQuote(asset: original, base: base, providerID: providerID)
            if !refresh, let cached, QuoteFreshness.isFresh(cached, now: now()) { return cached }
            let quote: MarketQuote
            do { quote = try await marketProvider.market(asset: original, base: base) }
            catch let failure as QuoteFailure where failure.permitsFallback {
                guard let cached, cached.dataTimestamp <= now(), cached.fetchedAt <= now() else { throw failure }
                return cached
            }
            try Task.checkCancellation()
            guard quote.asset == original, quote.base == base, quote.providerID == providerID,
                  quote.dataTimestamp <= now(), quote.fetchedAt <= now() else { throw QuoteFailure.malformedResponse }
            if let cached, cached.dataTimestamp > quote.dataTimestamp, cached.dataTimestamp <= now(), cached.fetchedAt <= now() { return cached }
            try await marketCache.saveMarketQuote(quote)
            return quote
        }
    }

    private func cachedFiat(original: CurrencyCode, base: CurrencyCode) async throws -> FiatQuote? {
        try await fiatCache.latestFiatQuote(original: original, base: base, providerID: fiatProvider.fiatProviderID)
    }

    private func requireCredentials() async throws {
        try Task.checkCancellation()
        guard let key = try await credentials.apiKey(), !key.isEmpty else { throw QuoteFailure.notConfigured }
    }
}

private extension QuoteFailure {
    var permitsFallback: Bool {
        switch self {
        case .noData, .offline, .timeout, .rateLimited, .unavailable, .malformedResponse: true
        default: false
        }
    }
}

/// Cancels an individual waiter immediately, and cancels transport when the final waiter leaves.
private actor SharedQuoteRequests<Key: Hashable & Sendable, Value: Sendable> {
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Value, any Error>]
    }
    private var flights: [Key: Flight] = [:]

    func value(for key: Key, load: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let waiter = UUID()
        let value: Value = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if flights[key] != nil {
                    flights[key]?.waiters[waiter] = continuation
                    return
                }
                let id = UUID()
                let task = Task {
                    do { finish(key, id: id, result: .success(try await load())) }
                    catch { finish(key, id: id, result: .failure(error)) }
                }
                flights[key] = Flight(id: id, task: task, waiters: [waiter: continuation])
            }
        } onCancel: {
            Task { await self.cancel(key, waiter: waiter) }
        }
        try Task.checkCancellation()
        return value
    }

    private func finish(_ key: Key, id: UUID, result: Result<Value, any Error>) {
        guard flights[key]?.id == id, let flight = flights.removeValue(forKey: key) else { return }
        for waiter in flight.waiters.values { waiter.resume(with: result) }
    }

    private func cancel(_ key: Key, waiter: UUID) {
        guard let continuation = flights[key]?.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if flights[key]?.waiters.isEmpty == true { flights.removeValue(forKey: key)?.task.cancel() }
    }
}
