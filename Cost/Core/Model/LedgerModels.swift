import Foundation

enum LedgerError: Error, Equatable, Sendable {
    case invalidField(String), invalidSnapshot, invalidTimeZone, dateOverflow
    case conflict, managedTransaction, invalidHierarchy, invalidCurrencyType, notFound
    case unsupportedDatabase, missingResource
    case storageConstraint, storageUnavailable
}

func requireText(_ text: String, _ field: String) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LedgerError.invalidField(field) }
}

func requireTimes(created: Int64, updated: Int64, deleted: Int64? = nil) throws {
    guard updated >= created, deleted.map({ (created...updated).contains($0) }) ?? true else {
        throw LedgerError.invalidField("timestamps")
    }
}

enum AssetType: String, Sendable { case fiat = "FIAT", crypto = "CRYPTO" }
enum TransactionType: String, Sendable { case expense = "EXPENSE", income = "INCOME" }
enum TransactionSource: String, Sendable { case manual = "MANUAL", template = "TEMPLATE", recurring = "RECURRING" }
enum ValuationMethod: String, Sendable {
    case identity = "IDENTITY", actualSettlement = "ACTUAL_SETTLEMENT", manualRate = "MANUAL_RATE"
    case latest = "LATEST_RATE", historical = "HISTORICAL_RATE", currentFallback = "CURRENT_FALLBACK"
    case cachedFallback = "CACHED_FALLBACK", marketPrice = "MARKET_PRICE", cachedMarketPrice = "CACHED_MARKET_PRICE"
    var isProviderBacked: Bool { ![Self.identity, .actualSettlement, .manualRate].contains(self) }
}
enum IconSource: String, Sendable { case builtIn = "BUILT_IN", emoji = "EMOJI", image = "IMAGE" }
enum BackgroundFocus: String, Sendable { case top = "TOP", center = "CENTER", bottom = "BOTTOM" }

struct LedgerVisual: Equatable, Sendable {
    var iconKey: String = "tag"
    var colorKey: String = "neutral"
    var source: IconSource = .builtIn
    var emoji: String?
    var iconAssetID: String?
    var backgroundAssetID: String?
    var backgroundFocus: BackgroundFocus = .center

    func validate() throws {
        try requireText(iconKey, "iconKey")
        try requireText(colorKey, "colorKey")
        switch source {
        case .builtIn:
            guard emoji == nil && iconAssetID == nil else { throw LedgerError.invalidField("visual") }
        case .emoji:
            guard let emoji, iconAssetID == nil else { throw LedgerError.invalidField("visual") }
            guard emoji.count == 1, emoji.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value == 0x20E3 }),
                  !emoji.unicodeScalars.allSatisfy({ (0x1F3FB...0x1F3FF).contains($0.value) })
            else { throw LedgerError.invalidField("emoji") }
        case .image:
            guard let iconAssetID, emoji == nil else { throw LedgerError.invalidField("visual") }
            try requireText(iconAssetID, "iconAssetID")
        }
        if let backgroundAssetID { try requireText(backgroundAssetID, "backgroundAssetID") }
    }
}

struct Currency: Equatable, Sendable {
    let code: CurrencyCode
    var assetType: AssetType
    var displayName: String
    var symbol: String
    var defaultScale: Int
    var isEnabled: Bool
    var sortOrder: Int64
    var metadataVersion: Int64

    func validate() throws {
        try requireText(displayName, "displayName")
        try requireText(symbol, "symbol")
        guard (0...18).contains(defaultScale), metadataVersion > 0 else { throw LedgerError.invalidField("currency") }
    }
}

struct Category: Equatable, Sendable {
    let id: String
    var name: String
    var type: TransactionType
    var parentID: String? = nil
    var visual = LedgerVisual()
    var sortOrder: Int64 = 0
    var isArchived = false
    let createdAt: Int64
    var updatedAt: Int64

    func validate() throws {
        try requireText(id, "categoryID")
        try requireText(name, "categoryName")
        guard parentID != id else { throw LedgerError.invalidHierarchy }
        if let parentID { try requireText(parentID, "parentID") }
        try visual.validate()
        try requireTimes(created: createdAt, updated: updatedAt)
    }
}

struct Account: Equatable, Sendable {
    let id: String
    var name: String
    var currencyCode: CurrencyCode? = nil
    var visual = LedgerVisual(iconKey: "wallet")
    var sortOrder: Int64 = 0
    var isDefault = false
    var isArchived = false
    let createdAt: Int64
    var updatedAt: Int64

    func validate() throws {
        try requireText(id, "accountID")
        try requireText(name, "accountName")
        guard !(isDefault && isArchived) else { throw LedgerError.invalidField("defaultAccount") }
        try visual.validate()
        try requireTimes(created: createdAt, updated: updatedAt)
    }
}

struct Tag: Equatable, Sendable {
    let id: String
    var name: String
    var colorKey: String = "neutral"
    var isArchived = false
    let createdAt: Int64
    var updatedAt: Int64

    static func normalize(_ name: String) -> String {
        name.precomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
    var normalizedName: String { Self.normalize(name) }

    func validate() throws {
        try requireText(id, "tagID")
        try requireText(name, "tagName")
        try requireText(normalizedName, "normalizedName")
        try requireText(colorKey, "colorKey")
        try requireTimes(created: createdAt, updated: updatedAt)
    }
}

struct OccurredAt: Equatable, Sendable {
    let epochMillis: Int64
    let zoneID: String
    let localEpochDay: Int64

    init(epochMillis: Int64, zoneID: String, localEpochDay: Int64? = nil) throws {
        guard let zone = TimeZone(identifier: zoneID) else { throw LedgerError.invalidTimeZone }
        // Date's TimeInterval is used only for timezone lookup, never financial arithmetic.
        let offset = Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(epochMillis) / 1000))) * 1000
        let shifted = epochMillis.addingReportingOverflow(offset)
        guard !shifted.overflow else { throw LedgerError.dateOverflow }
        let day = shifted.partialValue / 86_400_000 - (shifted.partialValue < 0 && shifted.partialValue % 86_400_000 != 0 ? 1 : 0)
        guard localEpochDay == nil || localEpochDay == day else { throw LedgerError.invalidField("localEpochDay") }
        self.epochMillis = epochMillis
        self.zoneID = zoneID
        self.localEpochDay = day
    }
}

struct ExchangeRateSnapshot: Equatable, Sendable {
    let rate: DecimalRate
    let providerID: String
    let dataTimestamp: Int64?
    let fetchedAt: Int64?
    let method: ValuationMethod

    func validate() throws {
        try requireText(providerID, "providerID")
        if method.isProviderBacked && (dataTimestamp == nil || fetchedAt == nil) { throw LedgerError.invalidSnapshot }
    }
}

enum CryptoPriceKind: String, Sendable {
    case actualPrice = "ACTUAL_PRICE", actualSettlement = "ACTUAL_SETTLEMENT", marketReference = "MARKET_REFERENCE"
}

struct CryptoValuationSnapshot: Equatable, Sendable {
    let price: DecimalRate
    let kind: CryptoPriceKind
    let source: String
    let venue: String
    let pair: String
    let dataTimestamp: Int64?
    let fetchedAt: Int64?
}

struct LedgerTransaction: Equatable, Sendable {
    let id: String
    let type: TransactionType
    let original: Money
    let convertedBase: Money
    let exchangeRate: ExchangeRateSnapshot
    let categoryID: String
    let accountID: String
    let occurredAt: OccurredAt
    let note: String?
    let source: TransactionSource
    let sourceID: String?
    let requestKey: String?
    let createdAt: Int64
    let updatedAt: Int64
    let deletedAt: Int64?
    let tagIDs: Set<String>
    let crypto: CryptoValuationSnapshot?

    init(id: String, type: TransactionType, original: Money, convertedBase: Money,
         exchangeRate: ExchangeRateSnapshot, categoryID: String, accountID: String,
         occurredAt: OccurredAt, note: String? = nil, source: TransactionSource = .manual,
         sourceID: String? = nil, requestKey: String? = nil, createdAt: Int64, updatedAt: Int64,
         deletedAt: Int64? = nil, tagIDs: Set<String> = [], crypto: CryptoValuationSnapshot? = nil) throws {
        self.id = id; self.type = type; self.original = original; self.convertedBase = convertedBase
        self.exchangeRate = exchangeRate; self.categoryID = categoryID; self.accountID = accountID
        self.occurredAt = occurredAt; self.note = note; self.source = source; self.sourceID = sourceID
        self.requestKey = requestKey; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.deletedAt = deletedAt; self.tagIDs = tagIDs; self.crypto = crypto
        try validate()
    }

    func validate() throws {
        try requireText(id, "transactionID")
        try requireText(categoryID, "categoryID")
        try requireText(accountID, "accountID")
        try requireTimes(created: createdAt, updated: updatedAt, deleted: deletedAt)
        try exchangeRate.validate()
        for id in tagIDs { try requireText(id, "tagID") }
        if let requestKey { try requireText(requestKey, "requestKey") }
        if source == .manual {
            guard sourceID == nil else { throw LedgerError.invalidField("sourceID") }
        } else {
            guard let sourceID else { throw LedgerError.invalidField("sourceID") }
            try requireText(sourceID, "sourceID")
        }
        if original.currencyCode == convertedBase.currencyCode {
            guard original == convertedBase, exchangeRate.rate.text == "1", exchangeRate.providerID == "IDENTITY",
                  exchangeRate.method == .identity, exchangeRate.dataTimestamp == nil, exchangeRate.fetchedAt == nil
            else { throw LedgerError.invalidSnapshot }
        } else {
            guard exchangeRate.method != .identity && exchangeRate.providerID != "IDENTITY" else { throw LedgerError.invalidSnapshot }
            if exchangeRate.method != .actualSettlement {
                guard try exchangeRate.rate.convert(original, to: convertedBase.currencyCode, scale: convertedBase.scale) == convertedBase
                else { throw LedgerError.invalidSnapshot }
            }
        }
        if let crypto {
            guard crypto.price == exchangeRate.rate, crypto.source == exchangeRate.providerID,
                  crypto.pair == original.currencyCode.rawValue + "/" + convertedBase.currencyCode.rawValue else {
                throw LedgerError.invalidSnapshot
            }
            try requireText(crypto.venue, "venue")
            switch crypto.kind {
            case .actualPrice:
                guard exchangeRate.method == .manualRate, crypto.dataTimestamp == nil, crypto.fetchedAt == nil,
                      exchangeRate.dataTimestamp == nil, exchangeRate.fetchedAt == nil else { throw LedgerError.invalidSnapshot }
            case .actualSettlement:
                guard exchangeRate.method == .actualSettlement, crypto.dataTimestamp == nil, crypto.fetchedAt == nil,
                      exchangeRate.dataTimestamp == nil, exchangeRate.fetchedAt == nil else { throw LedgerError.invalidSnapshot }
            case .marketReference:
                guard [.marketPrice, .cachedMarketPrice].contains(exchangeRate.method),
                      crypto.dataTimestamp == exchangeRate.dataTimestamp, crypto.fetchedAt == exchangeRate.fetchedAt,
                      let data = crypto.dataTimestamp, let fetched = crypto.fetchedAt, data > 0, fetched > 0
                else { throw LedgerError.invalidSnapshot }
            }
        } else if [.marketPrice, .cachedMarketPrice].contains(exchangeRate.method) {
            throw LedgerError.invalidSnapshot
        }
    }
}

enum QuoteKind: String, Sendable { case latest = "LATEST", historical = "HISTORICAL" }

struct FiatQuote: Equatable, Sendable {
    let id: String
    let original: CurrencyCode
    let base: CurrencyCode
    let rate: DecimalRate
    let providerID: String
    let dataTimestamp: Int64
    let rateEpochDay: Int64?
    let fetchedAt: Int64
    let expiresAt: Int64
    let kind: QuoteKind

    func validate() throws {
        try requireText(id, "quoteID")
        try requireText(providerID, "providerID")
        guard original != base, dataTimestamp > 0, fetchedAt > 0, expiresAt >= dataTimestamp,
              (kind == .historical) == (rateEpochDay != nil) else { throw LedgerError.invalidSnapshot }
    }
}

struct MarketQuote: Equatable, Sendable {
    let asset: CurrencyCode
    let base: CurrencyCode
    let providerID: String
    let price: DecimalRate
    let venue: String
    let dataTimestamp: Int64
    let fetchedAt: Int64
    let expiresAt: Int64

    func validate() throws {
        try requireText(providerID, "providerID")
        try requireText(venue, "venue")
        guard dataTimestamp > 0, fetchedAt > 0, expiresAt >= dataTimestamp else { throw LedgerError.invalidSnapshot }
    }
}
