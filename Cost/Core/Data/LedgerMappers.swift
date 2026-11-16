import GRDB

func storedEnum<T: RawRepresentable>(_ text: String, as type: T.Type) throws -> T where T.RawValue == String {
    guard let value = T(rawValue: text) else { throw LedgerError.invalidField("storedEnum") }
    return value
}

func storedRate(_ text: String) throws -> DecimalRate {
    let rate = try DecimalRate(text)
    guard rate.text == text else { throw LedgerError.invalidSnapshot }
    return rate
}

extension CurrencyRecord {
    func model() throws -> Currency {
        let value = Currency(code: try CurrencyCode(code), assetType: try storedEnum(asset_type, as: AssetType.self),
                             displayName: display_name, symbol: symbol, defaultScale: Int(default_scale),
                             isEnabled: is_enabled == 1, sortOrder: sort_order, metadataVersion: metadata_version)
        try value.validate()
        return value
    }
    init(_ value: Currency) {
        self.init(code: value.code.rawValue, asset_type: value.assetType.rawValue, display_name: value.displayName,
                  symbol: value.symbol, default_scale: Int64(value.defaultScale), is_enabled: value.isEnabled ? 1 : 0,
                  sort_order: value.sortOrder, metadata_version: value.metadataVersion)
    }
}

func storedVisual(iconKey: String, colorKey: String, source: String, emoji: String?, iconID: String?,
                  backgroundID: String?, focus: String) throws -> LedgerVisual {
    let visual = LedgerVisual(iconKey: iconKey, colorKey: colorKey, source: try storedEnum(source, as: IconSource.self),
                              emoji: emoji, iconAssetID: iconID, backgroundAssetID: backgroundID,
                              backgroundFocus: try storedEnum(focus, as: BackgroundFocus.self))
    try visual.validate()
    return visual
}

extension CategoryRecord {
    func model() throws -> Category {
        let value = Category(id: id, name: name, type: try storedEnum(transaction_type, as: TransactionType.self), parentID: parent_id,
            visual: try storedVisual(iconKey: icon_key, colorKey: color_key, source: icon_source, emoji: emoji,
                                     iconID: icon_asset_id, backgroundID: background_asset_id, focus: background_focus),
            sortOrder: sort_order, isArchived: is_archived == 1, createdAt: created_at_epoch_millis, updatedAt: updated_at_epoch_millis)
        try value.validate()
        return value
    }
    init(_ value: Category) {
        let visual = value.visual
        self.init(id: value.id, name: value.name, transaction_type: value.type.rawValue, parent_id: value.parentID,
                  icon_key: visual.iconKey, color_key: visual.colorKey, icon_source: visual.source.rawValue,
                  emoji: visual.emoji, icon_asset_id: visual.iconAssetID, background_asset_id: visual.backgroundAssetID,
                  background_focus: visual.backgroundFocus.rawValue, sort_order: value.sortOrder, is_archived: value.isArchived ? 1 : 0,
                  created_at_epoch_millis: value.createdAt, updated_at_epoch_millis: value.updatedAt)
    }
}

extension AccountRecord {
    func model() throws -> Account {
        let value = Account(id: id, name: name, currencyCode: try currency_code.map { try CurrencyCode($0) },
            visual: try storedVisual(iconKey: icon_key, colorKey: color_key, source: icon_source, emoji: emoji,
                                     iconID: icon_asset_id, backgroundID: background_asset_id, focus: background_focus),
            sortOrder: sort_order, isDefault: is_default == 1, isArchived: is_archived == 1,
            createdAt: created_at_epoch_millis, updatedAt: updated_at_epoch_millis)
        try value.validate()
        return value
    }
    init(_ value: Account) {
        let visual = value.visual
        self.init(id: value.id, name: value.name, currency_code: value.currencyCode?.rawValue,
                  icon_key: visual.iconKey, color_key: visual.colorKey, icon_source: visual.source.rawValue,
                  emoji: visual.emoji, icon_asset_id: visual.iconAssetID, background_asset_id: visual.backgroundAssetID,
                  background_focus: visual.backgroundFocus.rawValue, sort_order: value.sortOrder, is_default: value.isDefault ? 1 : 0,
                  is_archived: value.isArchived ? 1 : 0, created_at_epoch_millis: value.createdAt, updated_at_epoch_millis: value.updatedAt)
    }
}

extension TagRecord {
    func model() throws -> Tag {
        let value = Tag(id: id, name: name, colorKey: color_key, isArchived: is_archived == 1,
                        createdAt: created_at_epoch_millis, updatedAt: updated_at_epoch_millis)
        try value.validate()
        guard value.normalizedName == normalized_name else { throw LedgerError.invalidField("normalizedName") }
        return value
    }
    init(_ value: Tag) {
        self.init(id: value.id, name: value.name, normalized_name: value.normalizedName, color_key: value.colorKey,
                  is_archived: value.isArchived ? 1 : 0, created_at_epoch_millis: value.createdAt, updated_at_epoch_millis: value.updatedAt)
    }
}

extension TransactionRecord {
    init(_ value: LedgerTransaction) {
        self.init(id: value.id, transaction_type: value.type.rawValue, original_amount_minor: value.original.minorUnits,
                  original_scale: Int64(value.original.scale), original_currency_code: value.original.currencyCode.rawValue,
                  base_currency_code: value.convertedBase.currencyCode.rawValue, base_scale: Int64(value.convertedBase.scale),
                  exchange_rate_text: value.exchangeRate.rate.text, converted_base_amount_minor: value.convertedBase.minorUnits,
                  rate_data_timestamp: value.exchangeRate.dataTimestamp, rate_fetched_at: value.exchangeRate.fetchedAt,
                  rate_provider: value.exchangeRate.providerID, valuation_method: value.exchangeRate.method.rawValue,
                  category_id: value.categoryID, account_id: value.accountID, occurred_at_epoch_millis: value.occurredAt.epochMillis,
                  occurred_zone_id: value.occurredAt.zoneID, occurred_local_epoch_day: value.occurredAt.localEpochDay,
                  note: value.note, source_type: value.source.rawValue, source_id: value.sourceID, request_key: value.requestKey,
                  created_at_epoch_millis: value.createdAt, updated_at_epoch_millis: value.updatedAt, deleted_at_epoch_millis: value.deletedAt,
                  crypto_price_text: value.crypto?.price.text, crypto_price_kind: value.crypto?.kind.rawValue,
                  crypto_price_source: value.crypto?.source, crypto_venue: value.crypto?.venue, crypto_pair: value.crypto?.pair,
                  crypto_data_timestamp: value.crypto?.dataTimestamp, crypto_fetched_at: value.crypto?.fetchedAt)
    }

    func model(tagIDs: Set<String>) throws -> LedgerTransaction {
        let crypto: CryptoValuationSnapshot?
        if let price = crypto_price_text {
            guard let kind = crypto_price_kind, let source = crypto_price_source, let venue = crypto_venue, let pair = crypto_pair else {
                throw LedgerError.invalidSnapshot
            }
            crypto = CryptoValuationSnapshot(price: try storedRate(price), kind: try storedEnum(kind, as: CryptoPriceKind.self),
                                             source: source, venue: venue, pair: pair, dataTimestamp: crypto_data_timestamp, fetchedAt: crypto_fetched_at)
        } else {
            guard crypto_price_kind == nil, crypto_price_source == nil, crypto_venue == nil, crypto_pair == nil,
                  crypto_data_timestamp == nil, crypto_fetched_at == nil else { throw LedgerError.invalidSnapshot }
            crypto = nil
        }
        return try LedgerTransaction(id: id, type: storedEnum(transaction_type, as: TransactionType.self),
            original: Money(minorUnits: original_amount_minor, currencyCode: CurrencyCode(original_currency_code), scale: Int(original_scale)),
            convertedBase: Money(minorUnits: converted_base_amount_minor, currencyCode: CurrencyCode(base_currency_code), scale: Int(base_scale)),
            exchangeRate: ExchangeRateSnapshot(rate: storedRate(exchange_rate_text), providerID: rate_provider,
                dataTimestamp: rate_data_timestamp, fetchedAt: rate_fetched_at, method: storedEnum(valuation_method, as: ValuationMethod.self)),
            categoryID: category_id, accountID: account_id,
            occurredAt: OccurredAt(epochMillis: occurred_at_epoch_millis, zoneID: occurred_zone_id, localEpochDay: occurred_local_epoch_day),
            note: note, source: storedEnum(source_type, as: TransactionSource.self), sourceID: source_id, requestKey: request_key,
            createdAt: created_at_epoch_millis, updatedAt: updated_at_epoch_millis, deletedAt: deleted_at_epoch_millis, tagIDs: tagIDs, crypto: crypto)
    }
}

extension FiatQuoteRecord {
    init(_ value: FiatQuote) {
        self.init(id: value.id, original_currency_code: value.original.rawValue, base_currency_code: value.base.rawValue,
                  rate_text: value.rate.text, provider_id: value.providerID, rate_data_timestamp: value.dataTimestamp,
                  rate_date_epoch_day: value.rateEpochDay, fetched_at: value.fetchedAt, expires_at: value.expiresAt, quote_kind: value.kind.rawValue)
    }
    func model() throws -> FiatQuote {
        let value = try FiatQuote(id: id, original: CurrencyCode(original_currency_code), base: CurrencyCode(base_currency_code),
            rate: storedRate(rate_text), providerID: provider_id, dataTimestamp: rate_data_timestamp,
            rateEpochDay: rate_date_epoch_day, fetchedAt: fetched_at, expiresAt: expires_at, kind: storedEnum(quote_kind, as: QuoteKind.self))
        try value.validate()
        return value
    }
}

extension MarketQuoteRecord {
    init(_ value: MarketQuote) {
        self.init(asset_code: value.asset.rawValue, base_code: value.base.rawValue, provider_id: value.providerID,
                  price_text: value.price.text, venue: value.venue, data_timestamp: value.dataTimestamp,
                  fetched_at: value.fetchedAt, expires_at: value.expiresAt)
    }
    func model() throws -> MarketQuote {
        let value = try MarketQuote(asset: CurrencyCode(asset_code), base: CurrencyCode(base_code), providerID: provider_id,
                                   price: storedRate(price_text), venue: venue, dataTimestamp: data_timestamp,
                                   fetchedAt: fetched_at, expiresAt: expires_at)
        try value.validate()
        return value
    }
}
