import Foundation

extension AccountFundOpeningRecord {
    init(_ row: AccountFundOpening) {
        self.init(id: row.id, account_id: row.accountID, revision: row.revision, kind: row.kind.rawValue,
            enabled: row.enabled ? 1 : 0, currency_code: row.currencyCode.rawValue, scale: Int64(row.scale),
            amount_minor: row.amountMinor, started_at: row.startedAt, created_at: row.createdAt)
    }
    func model() throws -> AccountFundOpening {
        let row = try AccountFundOpening(id: id, accountID: account_id, revision: revision,
            kind: storedEnum(kind, as: AccountAmountKind.self), enabled: enabled == 1,
            currencyCode: CurrencyCode(currency_code), scale: Int(scale), amountMinor: amount_minor,
            startedAt: started_at, createdAt: created_at)
        try row.validate()
        return row
    }
}

extension AccountTransferRecord {
    init(_ row: AccountTransfer) {
        self.init(id: row.id, request_key: row.requestKey, from_account_id: row.fromAccountID, to_account_id: row.toAccountID,
            from_kind: row.fromKind.rawValue, to_kind: row.toKind.rawValue, currency_code: row.currencyCode.rawValue,
            scale: Int64(row.scale), principal_minor: row.principalMinor, profit_minor: row.profitMinor,
            profit_category_id: row.profitCategoryID, profit_transaction_id: row.profitTransactionID,
            occurred_at: row.occurredAt.epochMillis, zone_id: row.occurredAt.zoneID, note: row.note,
            created_at: row.createdAt, updated_at: row.updatedAt, deleted_at: row.deletedAt)
    }
    func model() throws -> AccountTransfer {
        let row = try AccountTransfer(id: id, requestKey: request_key, fromAccountID: from_account_id, toAccountID: to_account_id,
            fromKind: storedEnum(from_kind, as: AccountAmountKind.self), toKind: storedEnum(to_kind, as: AccountAmountKind.self),
            currencyCode: CurrencyCode(currency_code), scale: Int(scale), principalMinor: principal_minor,
            profitMinor: profit_minor, profitCategoryID: profit_category_id, profitTransactionID: profit_transaction_id,
            occurredAt: OccurredAt(epochMillis: occurred_at, zoneID: zone_id), note: note, createdAt: created_at,
            updatedAt: updated_at, deletedAt: deleted_at)
        try row.validate()
        return row
    }
}
