import GRDB

extension GRDBLedgerRepository: AccountFundsRepository {
    static func latestOpening(_ db: Database, accountID: String) throws -> AccountFundOpening? {
        try AccountFundOpeningRecord.fetchOne(db, sql: "SELECT * FROM account_fund_openings WHERE account_id = ? ORDER BY revision DESC LIMIT 1", arguments: [accountID])?.model()
    }
    func latestOpening(accountID: String) async throws -> AccountFundOpening? {
        try await read { db in try Self.latestOpening(db, accountID: accountID) }
    }
    private static func requireActiveAccount(_ db: Database, id: String) throws {
        guard try AccountRecord.fetchOne(db, key: id)?.is_archived == 0 else { throw FundsError.accountUnavailable }
    }
    private static func requireFundCurrency(_ db: Database, code: CurrencyCode) throws -> Currency {
        guard let currency = try CurrencyRecord.fetchOne(db, key: code.rawValue)?.model(), currency.isEnabled, currency.assetType == .fiat
        else { throw FundsError.currencyUnavailable }
        return currency
    }
    func saveOpening(_ opening: AccountFundOpening) async throws -> AccountFundOpening {
        try opening.validate()
        return try await write { db in
            try Self.requireActiveAccount(db, id: opening.accountID)
            let currency = try Self.requireFundCurrency(db, code: opening.currencyCode)
            guard currency.defaultScale == opening.scale else { throw FundsError.currencyUnavailable }
            let latest = try Self.latestOpening(db, accountID: opening.accountID)
            let next = (latest?.revision ?? 0).addingReportingOverflow(1)
            guard !next.overflow else { throw FundsError.overflow }
            var saved = opening
            saved.revision = next.partialValue
            try AccountFundOpeningRecord(saved).insert(db)
            return saved
        }
    }
    /// One SQLite snapshot, cursor accumulation and no persisted running balances.
    static func positions(_ db: Database) throws -> [AccountPosition] {
        try AccountRecord.fetchAll(db, sql: "SELECT * FROM accounts ORDER BY sort_order, id").map { account in
            let opening = try latestOpening(db, accountID: account.id)
            guard let opening, opening.enabled, let units = opening.amountMinor else {
                return AccountPosition(accountID: account.id, opening: opening, amount: nil, unvaluedCount: 0)
            }
            var total = FundAmount(units: units, scale: opening.scale)
            var missing = 0
            if opening.kind == .available {
                let cursor = try TransactionRecord.fetchCursor(db, sql: "SELECT * FROM transactions WHERE account_id = ? AND deleted_at_epoch_millis IS NULL AND occurred_at_epoch_millis >= ?", arguments: [account.id, opening.startedAt])
                while let row = try cursor.next() {
                    guard opening.includes(occurred: row.occurred_at_epoch_millis, created: row.created_at_epoch_millis) else { continue }
                    if row.original_currency_code == opening.currencyCode.rawValue {
                        total.add(units: row.original_amount_minor, scale: Int(row.original_scale), subtract: row.transaction_type == "EXPENSE")
                    } else if row.base_currency_code == opening.currencyCode.rawValue {
                        total.add(units: row.converted_base_amount_minor, scale: Int(row.base_scale), subtract: row.transaction_type == "EXPENSE")
                    } else { missing += 1 }
                }
            }
            let cursor = try AccountTransferRecord.fetchCursor(db, sql: "SELECT * FROM account_transfers WHERE (from_account_id = ? OR to_account_id = ?) AND deleted_at IS NULL AND occurred_at >= ?", arguments: [account.id, account.id, opening.startedAt])
            while let row = try cursor.next() {
                guard opening.includes(occurred: row.occurred_at, created: row.created_at) else { continue }
                if row.currency_code != opening.currencyCode.rawValue { missing += 1; continue }
                total.add(units: row.principal_minor, scale: Int(row.scale), subtract: row.from_account_id == account.id)
            }
            return AccountPosition(accountID: account.id, opening: opening, amount: total, unvaluedCount: missing)
        }
    }
    func positions() async throws -> [AccountPosition] { try await read { db in try Self.positions(db) } }
    func transfers(limit: Int = 200) async throws -> [AccountTransfer] {
        guard (1...2000).contains(limit) else { throw LedgerError.invalidField("limit") }
        return try await read { db in
            try AccountTransferRecord.fetchAll(db, sql: "SELECT * FROM account_transfers ORDER BY occurred_at DESC, id DESC LIMIT ?", arguments: [limit]).map { try $0.model() }
        }
    }
    func transfer(id: String) async throws -> AccountTransfer? {
        try await read { db in try AccountTransferRecord.fetchOne(db, key: id)?.model() }
    }
    private static func validatePositions(_ db: Database, transfer: AccountTransfer, checkSource: Bool) throws {
        for position in try positions(db) where position.accountID == transfer.fromAccountID || position.accountID == transfer.toAccountID {
            guard let opening = position.opening, opening.enabled else { continue }
            let applies = transfer.deletedAt == nil && opening.includes(occurred: transfer.occurredAt.epochMillis, created: transfer.createdAt)
            if applies && opening.currencyCode != transfer.currencyCode { throw FundsError.currencyMismatch }
            if applies && position.unvaluedCount > 0 { throw FundsError.unvaluedTransactions }
            if position.amount?.isNegative == true && (opening.kind == .investmentCost || (checkSource && applies && position.accountID == transfer.fromAccountID)) {
                throw FundsError.insufficientFunds
            }
        }
    }
    func saveTransfer(_ transfer: AccountTransfer, expectedUpdatedAt: Int64?) async throws -> AccountTransfer {
        try transfer.validate()
        return try await write { db in
            let current = try AccountTransferRecord.fetchOne(db, key: transfer.id)?.model()
            if current == nil, let duplicate = try AccountTransferRecord.fetchOne(db, sql: "SELECT * FROM account_transfers WHERE request_key = ?", arguments: [transfer.requestKey])?.model() {
                guard transfer.samePayload(as: duplicate), duplicate.deletedAt == nil else { throw LedgerError.conflict }
                return duplicate
            }
            if let current {
                guard current.deletedAt == nil, current.updatedAt == expectedUpdatedAt, current.requestKey == transfer.requestKey,
                      current.createdAt == transfer.createdAt, transfer.updatedAt > current.updatedAt else { throw LedgerError.conflict }
            } else if expectedUpdatedAt != nil { throw LedgerError.conflict }
            guard transfer.deletedAt == nil else { throw LedgerError.conflict }
            try Self.requireActiveAccount(db, id: transfer.fromAccountID)
            try Self.requireActiveAccount(db, id: transfer.toAccountID)
            let currency = try Self.requireFundCurrency(db, code: transfer.currencyCode)
            guard transfer.scale == (current?.currencyCode == currency.code ? current?.scale : currency.defaultScale) else { throw FundsError.currencyUnavailable }
            for (id, kind) in [(transfer.fromAccountID, transfer.fromKind), (transfer.toAccountID, transfer.toKind)] {
                let oldKind = current.flatMap { id == $0.fromAccountID ? $0.fromKind : (id == $0.toAccountID ? $0.toKind : nil) }
                let kindNow = try Self.latestOpening(db, accountID: id)?.kind ?? .available
                guard kind == (oldKind ?? kindNow) else { throw LedgerError.conflict }
            }
            var saved = transfer
            saved.profitTransactionID = current?.profitTransactionID
            let previous = try current?.profitTransactionID.flatMap { try Self.find(db, id: $0) }
            if transfer.profitMinor != 0 {
                guard let id = transfer.profitCategoryID, let category = try CategoryRecord.fetchOne(db, key: id), category.is_archived == 0,
                      category.transaction_type == (transfer.profitMinor > 0 ? "INCOME" : "EXPENSE") else { throw FundsError.categoryRequired }
                let profit = try transfer.profitTransaction(existing: previous)
                if previous == nil { try TransactionRecord(profit).insert(db) }
                else { try TransactionRecord(profit).update(db) }
                saved.profitTransactionID = profit.id
            } else if let previous {
                try db.execute(sql: "UPDATE transactions SET deleted_at_epoch_millis = ?, updated_at_epoch_millis = ? WHERE id = ?", arguments: [transfer.updatedAt, transfer.updatedAt, previous.id])
                saved.profitTransactionID = previous.id
            }
            try AccountTransferRecord(saved).save(db)
            try Self.validatePositions(db, transfer: saved, checkSource: true)
            return saved
        }
    }
    func setTransferDeleted(id: String, deleted: Bool, at timestamp: Int64) async throws {
        try await write { db in
            guard var current = try AccountTransferRecord.fetchOne(db, key: id)?.model() else { throw LedgerError.notFound }
            if (current.deletedAt != nil) == deleted { return }
            if !deleted {
                try Self.requireActiveAccount(db, id: current.fromAccountID)
                try Self.requireActiveAccount(db, id: current.toAccountID)
            }
            let next = current.updatedAt.addingReportingOverflow(1)
            guard !next.overflow else { throw LedgerError.dateOverflow }
            current.updatedAt = max(timestamp, next.partialValue)
            current.deletedAt = deleted ? current.updatedAt : nil
            if let profitID = current.profitTransactionID, deleted || current.profitMinor != 0 {
                try db.execute(sql: "UPDATE transactions SET deleted_at_epoch_millis = ?, updated_at_epoch_millis = ? WHERE id = ?",
                    arguments: [deleted ? current.updatedAt : nil, current.updatedAt, profitID])
            }
            try AccountTransferRecord(current).update(db)
            try Self.validatePositions(db, transfer: current, checkSource: !deleted)
        }
    }
}
