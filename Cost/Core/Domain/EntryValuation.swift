import Foundation

protocol BaseCurrencyPreferences: Sendable {
    func baseCurrencyCode() async -> String
    func setBaseCurrencyCode(_ code: String) async throws
}

func preferredBaseCurrency(_ preferences: (any BaseCurrencyPreferences)?, in repository: any CurrencyRepository) async throws -> Currency {
    let code = await preferences?.baseCurrencyCode() ?? EntryDraft.defaultBaseCurrencyCode
    if let code = try? CurrencyCode(code), let currency = try await repository.currency(code: code),
       currency.assetType == .fiat, currency.isEnabled { return currency }
    guard let fallback = try await repository.currency(code: CurrencyCode(EntryDraft.defaultBaseCurrencyCode)),
          fallback.assetType == .fiat, fallback.isEnabled else { throw LedgerError.invalidCurrencyType }
    return fallback
}

struct EntryValuation: Equatable, Sendable {
    let converted: Money
    let rate: ExchangeRateSnapshot
    var crypto: CryptoValuationSnapshot? = nil

    static func resolve(original: Money, base: CurrencyCode, scale: Int, type: AssetType,
                        occurredAt: OccurredAt, now: Int64,
                        actualText: String = "", rateText: String = "", offer: ValuationOffer? = nil,
                        confirmed: Bool = false) throws -> Self {
        if original.currencyCode == base {
            guard original.scale == scale else { throw LedgerError.invalidSnapshot }
            return try Self(converted: original, rate: .identity())
        }
        if !actualText.isEmpty {
            let actual = try Money.parse(actualText, currencyCode: base, scale: scale)
            let rate = try DecimalRate.derived(actual: actual, original: original)
            return make(original, actual, type: type, rate: rate, source: type == .crypto ? "CRYPTO_ACTUAL_SETTLEMENT" : "ACTUAL_SETTLEMENT",
                        method: .actualSettlement, kind: .actualSettlement)
        }
        if !rateText.isEmpty {
            let rate = try DecimalRate(rateText)
            return make(original, try rate.convert(original, to: base, scale: scale), type: type, rate: rate,
                        source: type == .crypto ? "CRYPTO_ACTUAL_PRICE" : "MANUAL", method: .manualRate, kind: .actualPrice)
        }
        guard let offer else { throw type == .crypto ? QuoteFailure.confirmationRequired : QuoteFailure.notConfigured }
        guard offer.original == original.currencyCode, offer.base == base,
              offer.day == occurredAt.localEpochDay, offer.zoneID == occurredAt.zoneID,
              (offer.venue != nil) == (type == .crypto) else { throw LedgerError.invalidSnapshot }
        let today = try OccurredAt(epochMillis: now, zoneID: occurredAt.zoneID).localEpochDay
        if type == .crypto && today != offer.day { throw QuoteFailure.cryptoHistorical }
        if offer.snapshot.method == .latest && today != offer.day { throw QuoteFailure.notConfigured }
        guard offer.at(now) == offer else { throw QuoteFailure.confirmationRequired }
        guard !offer.requiresConfirmation || confirmed else { throw QuoteFailure.confirmationRequired }
        let snapshot = offer.snapshot
        return make(original, try snapshot.rate.convert(original, to: base, scale: scale), type: type, rate: snapshot.rate,
                    source: snapshot.providerID, method: snapshot.method, kind: .marketReference,
                    venue: offer.venue ?? "USER", data: snapshot.dataTimestamp, fetched: snapshot.fetchedAt)
    }

    private static func make(_ original: Money, _ converted: Money, type: AssetType, rate: DecimalRate,
                             source: String, method: ValuationMethod, kind: CryptoPriceKind,
                             venue: String = "USER", data: Int64? = nil, fetched: Int64? = nil) -> Self {
        let snapshot = ExchangeRateSnapshot(rate: rate, providerID: source, dataTimestamp: data, fetchedAt: fetched, method: method)
        let crypto = type == .crypto ? CryptoValuationSnapshot(price: rate, kind: kind, source: source, venue: venue,
            pair: "\(original.currencyCode.rawValue)/\(converted.currencyCode.rawValue)", dataTimestamp: data, fetchedAt: fetched) : nil
        return Self(converted: converted, rate: snapshot, crypto: crypto)
    }
}
