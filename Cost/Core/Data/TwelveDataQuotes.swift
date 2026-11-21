import Foundation

struct QuoteHTTPResponse: Sendable {
    let status: Int
    let retryAfter: String?
    let body: Data
}

protocol QuoteHTTPTransport: Sendable {
    func fetch(_ request: URLRequest) async throws -> QuoteHTTPResponse
}

final class TwelveDataTransport: NSObject, URLSessionTaskDelegate, QuoteHTTPTransport {
    static let bodyLimit = 65_536

    func fetch(_ request: URLRequest) async throws -> QuoteHTTPResponse {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw QuoteFailure.malformedResponse }
        guard http.expectedContentLength <= Int64(Self.bodyLimit) else { throw QuoteFailure.malformedResponse }
        var body = Data()
        for try await byte in bytes {
            guard body.count < Self.bodyLimit else { throw QuoteFailure.malformedResponse }
            body.append(byte)
        }
        return QuoteHTTPResponse(status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"), body: body)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

struct TwelveDataQuotes: FiatRateProvider, MarketPriceProvider {
    let fiatProviderID = "TWELVE_DATA_FOREX_V2"
    let marketProviderID = "TWELVE_DATA_CRYPTO_QUOTE"
    let credentials: any QuoteCredentials
    let transport: any QuoteHTTPTransport
    var now: @Sendable () -> Int64
    var delay: @Sendable (Int64) async throws -> Void = { try await Task.sleep(for: .milliseconds($0)) }

    func fiat(original: CurrencyCode, base: CurrencyCode, epochDay: Int64?) async throws -> FiatQuote {
        let symbol = original.rawValue + "/" + base.rawValue
        var options: [URLQueryItem] = []
        if let epochDay {
            let (milliseconds, overflow) = epochDay.multipliedReportingOverflow(by: 86_400_000)
            guard !overflow, milliseconds >= 0, epochDay <= 2_932_896 else { throw QuoteFailure.invalidRequest }
            let date = Date(timeIntervalSince1970: TimeInterval(milliseconds / 1000))
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = TimeZone(secondsFromGMT: 0)
            format.dateFormat = "yyyy-MM-dd'T'23:59:59"
            options.append(URLQueryItem(name: "date", value: format.string(from: date)))
        }
        let payload = try await request(path: "/exchange_rate", symbol: symbol, options: options, historical: epochDay != nil)
        let data = try payload.timestampMillis()
        let fetched = now()
        if let epochDay {
            guard data / 86_400_000 == epochDay else { throw QuoteFailure.noData }
        } else {
            guard data <= fetched else { throw QuoteFailure.malformedResponse }
        }
        let rate = try payload.decimal(payload.rate)
        let kind: QuoteKind = epochDay == nil ? .latest : .historical
        return FiatQuote(id: "\(fiatProviderID):\(symbol):\(kind.rawValue):\(data)", original: original,
            base: base, rate: rate, providerID: fiatProviderID, dataTimestamp: data, rateEpochDay: epochDay,
            fetchedAt: fetched, expiresAt: data + QuoteFreshness.lifetime, kind: kind)
    }

    func market(asset: CurrencyCode, base: CurrencyCode) async throws -> MarketQuote {
        let symbol = asset.rawValue + "/" + base.rawValue
        let payload = try await request(path: "/quote", symbol: symbol,
            options: [URLQueryItem(name: "interval", value: "1min")], historical: false)
        let data = try payload.timestampMillis()
        let fetched = now()
        guard data <= fetched, let venue = payload.exchange, (1...128).contains(venue.count),
              !venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !venue.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw QuoteFailure.malformedResponse }
        return MarketQuote(asset: asset, base: base, providerID: marketProviderID, price: try payload.decimal(payload.close),
            venue: venue, dataTimestamp: data, fetchedAt: fetched, expiresAt: data + QuoteFreshness.lifetime)
    }

    private func request(path: String, symbol: String, options: [URLQueryItem], historical: Bool) async throws -> Payload {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "api.twelvedata.com"
        url.path = path
        url.queryItems = [URLQueryItem(name: "symbol", value: symbol), URLQueryItem(name: "dp", value: "11"),
            URLQueryItem(name: "timezone", value: "UTC")] + options
        guard let endpoint = url.url else { throw QuoteFailure.invalidRequest }
        for attempt in 0..<3 {
            try Task.checkCancellation()
            guard let key = try await credentials.apiKey(), !key.isEmpty else { throw QuoteFailure.notConfigured }
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue("apikey \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response: QuoteHTTPResponse
            do { response = try await transport.fetch(request) }
            catch let error as URLError {
                if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
                guard error.code == .timedOut else { throw mapTransport(error.code) }
                guard attempt < 2 else { throw QuoteFailure.timeout }
                try await delay(attempt == 0 ? 250 : 500)
                continue
            } catch let error as QuoteFailure { throw error }
            catch is CancellationError { throw CancellationError() }
            catch { throw QuoteFailure.unavailable }
            try Task.checkCancellation()
            let payload = try? Payload.read(response.body)
            let status = (200..<300).contains(response.status)
                ? (payload?.status == "error" ? Int(payload?.code ?? "") ?? 400 : response.status)
                : response.status
            switch status {
            case 200..<300:
                guard let payload, payload.symbol?.uppercased() == symbol, payload.status != "error" else {
                    throw QuoteFailure.malformedResponse
                }
                return payload
            case 401, 403: throw QuoteFailure.unauthorized
            case 404, 422: throw QuoteFailure.noData
            case 400 where historical: throw QuoteFailure.noData
            case 429, 500...599:
                guard attempt < 2 else { throw status == 429 ? QuoteFailure.rateLimited : QuoteFailure.unavailable }
                let backoff: Int64 = attempt == 0 ? 250 : 500
                try await delay(status == 429 ? max(backoff, retryDelay(response.retryAfter)) : backoff)
            default: throw QuoteFailure.invalidRequest
            }
        }
        throw QuoteFailure.unavailable
    }

    private func mapTransport(_ code: URLError.Code) -> QuoteFailure {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed: .offline
        default: .unavailable
        }
    }

    private func retryDelay(_ value: String?) -> Int64 {
        guard let value else { return 0 }
        if let seconds = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return min(30, max(0, seconds)) * 1000 }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = format.date(from: value) else { return 0 }
        return Int64(min(30_000, max(0, date.timeIntervalSince1970 * 1000 - TimeInterval(now()))))
    }

    private struct Payload: Decodable {
        let symbol: String?
        let rate: String?
        let close: String?
        let timestamp: String?
        let exchange: String?
        let status: String?
        let code: String?

        private struct Object: Decodable { }

        static func read(_ data: Data) throws -> Self {
            guard data.count <= TwelveDataTransport.bodyLimit, let json = String(data: data, encoding: .utf8) else {
                throw QuoteFailure.malformedResponse
            }
            let decoder = JSONDecoder()
            // Validate the original grammar without decoding numeric values. Convert complete numeric lexemes to strings.
            _ = try decoder.decode(Object.self, from: data)
            let syntax = /"(?:[^"\\]|\\.)*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/
            let exact = json.replacing(syntax) { token in
                token.output.first == "\"" ? String(token.output) : "\"\(token.output)\""
            }
            return try decoder.decode(Self.self, from: Data(exact.utf8))
        }

        func decimal(_ value: String?) throws -> DecimalRate {
            guard let value, value.utf8.count <= 80, let rate = try? DecimalRate(value) else { throw QuoteFailure.malformedResponse }
            return rate
        }

        func timestampMillis() throws -> Int64 {
            guard let timestamp, let seconds = Int64(timestamp), seconds > 0,
                  seconds <= (Int64.max - QuoteFreshness.lifetime) / 1000 else { throw QuoteFailure.malformedResponse }
            return seconds * 1000
        }
    }
}
