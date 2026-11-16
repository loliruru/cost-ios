import GRDB

struct LedgerRepositories: Sendable {
    let currencies: any CurrencyRepository
    let categories: any CategoryRepository
    let accounts: any AccountRepository
    let tags: any TagRepository
    let transactions: any TransactionRepository
    let fiatQuotes: any FiatQuoteRepository
    let marketQuotes: any MarketQuoteRepository

    init(database: AppDatabase) {
        let repository = GRDBLedgerRepository(database: database)
        currencies = repository; categories = repository; accounts = repository; tags = repository
        transactions = repository; fiatQuotes = repository; marketQuotes = repository
    }
}

struct GRDBLedgerRepository: CurrencyRepository, CategoryRepository, AccountRepository, TagRepository,
                             TransactionRepository, FiatQuoteRepository, MarketQuoteRepository {
    let database: AppDatabase

    private func read<T: Sendable>(_ operation: @escaping @Sendable (Database) throws -> T) async throws -> T {
        do { return try await database.writer.read(operation) }
        catch let error as DatabaseError { throw Self.storageError(error) }
    }

    private func write<T: Sendable>(_ operation: @escaping @Sendable (Database) throws -> T) async throws -> T {
        do { return try await database.writer.write(operation) }
        catch let error as DatabaseError { throw Self.storageError(error) }
    }

    private static func storageError(_ error: DatabaseError) -> LedgerError {
        error.resultCode == .SQLITE_CONSTRAINT ? .storageConstraint : .storageUnavailable
    }

    func currencies(includeDisabled: Bool = true) async throws -> [Currency] {
        try await read { db in
            try CurrencyRecord.fetchAll(db, sql: "SELECT * FROM currencies WHERE ? OR is_enabled = 1 ORDER BY sort_order, code",
                                        arguments: [includeDisabled]).map { try $0.model() }
        }
    }
    func currency(code: CurrencyCode) async throws -> Currency? {
        try await read { db in try CurrencyRecord.fetchOne(db, key: code.rawValue)?.model() }
    }
    func saveCurrency(_ currency: Currency) async throws {
        try currency.validate()
        try await write { db in
            if let old = try CurrencyRecord.fetchOne(db, key: currency.code.rawValue), old.asset_type != currency.assetType.rawValue {
                throw LedgerError.invalidCurrencyType
            }
            try CurrencyRecord(currency).save(db)
        }
    }

    func categories(includeArchived: Bool = false) async throws -> [Category] {
        try await read { db in
            try CategoryRecord.fetchAll(db, sql: "SELECT * FROM categories WHERE ? OR is_archived = 0 ORDER BY sort_order, id",
                                        arguments: [includeArchived]).map { try $0.model() }
        }
    }
    func category(id: String) async throws -> Category? {
        try await read { db in try CategoryRecord.fetchOne(db, key: id)?.model() }
    }
    func saveCategory(_ category: Category) async throws {
        try category.validate()
        try await write { db in
            if let old = try CategoryRecord.fetchOne(db, key: category.id) {
                guard old.created_at_epoch_millis == category.createdAt, category.updatedAt >= old.updated_at_epoch_millis else {
                    throw LedgerError.conflict
                }
            }
            if let parent = category.parentID {
                guard let row = try CategoryRecord.fetchOne(db, key: parent), row.parent_id == nil,
                      row.transaction_type == category.type.rawValue, category.isArchived || row.is_archived == 0
                else { throw LedgerError.invalidHierarchy }
            }
            try CategoryRecord(category).save(db)
            if category.isArchived { try Self.archiveChildren(db, id: category.id, at: category.updatedAt) }
        }
    }
    private static func archiveChildren(_ db: Database, id: String, at timestamp: Int64) throws {
        let future = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM categories WHERE parent_id = ? AND updated_at_epoch_millis > ?)", arguments: [id, timestamp]) ?? false
        guard !future else { throw LedgerError.conflict }
        try db.execute(sql: "UPDATE categories SET is_archived = 1, updated_at_epoch_millis = ? WHERE parent_id = ?", arguments: [timestamp, id])
    }
    func archiveCategory(id: String, at timestamp: Int64) async throws {
        try await write { db in
            guard var row = try CategoryRecord.fetchOne(db, key: id) else { throw LedgerError.notFound }
            guard timestamp >= row.updated_at_epoch_millis else { throw LedgerError.conflict }
            row.is_archived = 1
            row.updated_at_epoch_millis = timestamp
            try row.update(db)
            try Self.archiveChildren(db, id: id, at: timestamp)
        }
    }
    func deleteArchivedCategory(id: String) async throws -> CategoryDeletionResult {
        try await write { db in
            guard let row = try CategoryRecord.fetchOne(db, key: id) else { return .notFound }
            guard row.is_archived == 1 else { return .notArchived }
            if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM categories WHERE parent_id = ?)", arguments: [id]) == true {
                return .hasChildren
            }
            for (table, column) in [("transactions", "category_id"), ("quick_templates", "category_id"),
                                    ("recurring_rules", "category_id"), ("account_transfers", "profit_category_id"),
                                    ("anomaly_feedback", "category_id")] {
                if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM \(table) WHERE \(column) = ?)", arguments: [id]) == true {
                    return .inUse
                }
            }
            _ = try row.delete(db)
            return .deleted
        }
    }

    func accounts(includeArchived: Bool = false) async throws -> [Account] {
        try await read { db in
            try AccountRecord.fetchAll(db, sql: "SELECT * FROM accounts WHERE ? OR is_archived = 0 ORDER BY sort_order, id",
                                       arguments: [includeArchived]).map { try $0.model() }
        }
    }
    func account(id: String) async throws -> Account? {
        try await read { db in try AccountRecord.fetchOne(db, key: id)?.model() }
    }
    func saveAccount(_ account: Account) async throws {
        try account.validate()
        try await write { db in
            if let old = try AccountRecord.fetchOne(db, key: account.id) {
                guard old.created_at_epoch_millis == account.createdAt, account.updatedAt >= old.updated_at_epoch_millis else {
                    throw LedgerError.conflict
                }
            }
            if account.isDefault {
                try db.execute(sql: "UPDATE accounts SET is_default = 0, updated_at_epoch_millis = MAX(updated_at_epoch_millis, ?) WHERE is_default = 1 AND id <> ?",
                               arguments: [account.updatedAt, account.id])
            }
            try AccountRecord(account).save(db)
        }
    }

    func tags(includeArchived: Bool = false) async throws -> [Tag] {
        try await read { db in
            try TagRecord.fetchAll(db, sql: "SELECT * FROM tags WHERE ? OR is_archived = 0 ORDER BY normalized_name, id",
                                   arguments: [includeArchived]).map { try $0.model() }
        }
    }
    func tag(id: String) async throws -> Tag? {
        try await read { db in try TagRecord.fetchOne(db, key: id)?.model() }
    }
    func saveTag(_ tag: Tag) async throws -> Tag {
        try tag.validate()
        return try await write { db in
            let old = try TagRecord.fetchOne(db, key: tag.id)
            let collision = try TagRecord.fetchOne(db, sql: "SELECT * FROM tags WHERE normalized_name = ?", arguments: [tag.normalizedName])
            if var collision, collision.id != tag.id {
                guard old == nil else { throw LedgerError.conflict }
                collision.is_archived = 0
                collision.updated_at_epoch_millis = max(collision.updated_at_epoch_millis, tag.updatedAt)
                try collision.update(db)
                return try collision.model()
            }
            if let old {
                guard old.created_at_epoch_millis == tag.createdAt, tag.updatedAt >= old.updated_at_epoch_millis else { throw LedgerError.conflict }
            }
            try TagRecord(tag).save(db)
            return tag
        }
    }
    func deleteArchivedTag(id: String) async throws -> Bool {
        try await write { db in
            guard let row = try TagRecord.fetchOne(db, key: id), row.is_archived == 1 else { return false }
            for table in ["transaction_tags", "quick_template_tags", "recurring_rule_tags"] {
                try db.execute(sql: "DELETE FROM \(table) WHERE tag_id = ?", arguments: [id])
            }
            return try row.delete(db)
        }
    }

    private static func load(_ db: Database, sql: String, arguments: StatementArguments) throws -> [LedgerTransaction] {
        let rows = try TransactionRecord.fetchAll(db, sql: sql, arguments: arguments)
        guard !rows.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: rows.count).joined(separator: ",")
        let references = try TransactionTagRecord.fetchAll(db, sql: "SELECT * FROM transaction_tags WHERE transaction_id IN (\(placeholders))",
                                                          arguments: StatementArguments(rows.map(\.id)))
        var tags: [String: Set<String>] = [:]
        for reference in references { tags[reference.transaction_id, default: []].insert(reference.tag_id) }
        return try rows.map { try $0.model(tagIDs: tags[$0.id, default: []]) }
    }

    private static func find(_ db: Database, id: String) throws -> LedgerTransaction? {
        try load(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id]).first
    }
    private static func checkManaged(_ db: Database, id: String) throws {
        if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM account_transfers WHERE profit_transaction_id = ?)", arguments: [id]) == true {
            throw LedgerError.managedTransaction
        }
    }
    private static func validateCurrencies(_ db: Database, transaction: LedgerTransaction) throws {
        let original = try CurrencyRecord.fetchOne(db, key: transaction.original.currencyCode.rawValue)
        let base = try CurrencyRecord.fetchOne(db, key: transaction.convertedBase.currencyCode.rawValue)
        guard let original, let base, base.asset_type == "FIAT",
              (original.asset_type == "CRYPTO") == (transaction.crypto != nil) else { throw LedgerError.invalidCurrencyType }
        guard let category = try CategoryRecord.fetchOne(db, key: transaction.categoryID), category.transaction_type == transaction.type.rawValue else {
            throw LedgerError.invalidHierarchy
        }
    }
    private static func replaceTags(_ db: Database, transaction: LedgerTransaction) throws {
        try db.execute(sql: "DELETE FROM transaction_tags WHERE transaction_id = ?", arguments: [transaction.id])
        for id in transaction.tagIDs.sorted() {
            try TransactionTagRecord(transaction_id: transaction.id, tag_id: id).insert(db)
        }
    }

    func createTransaction(_ transaction: LedgerTransaction) async throws -> LedgerTransaction {
        try transaction.validate()
        return try await write { db in
            if let key = transaction.requestKey,
               let existing = try Self.load(db, sql: "SELECT * FROM transactions WHERE request_key = ?", arguments: [key]).first {
                return existing
            }
            if let existing = try Self.find(db, id: transaction.id) {
                guard existing == transaction else { throw LedgerError.conflict }
                return existing
            }
            try Self.validateCurrencies(db, transaction: transaction)
            try TransactionRecord(transaction).insert(db)
            try Self.replaceTags(db, transaction: transaction)
            return transaction
        }
    }

    func updateTransaction(_ transaction: LedgerTransaction, expectedUpdatedAt: Int64) async throws -> Bool {
        try transaction.validate()
        return try await write { db in
            try Self.checkManaged(db, id: transaction.id)
            guard let old = try Self.find(db, id: transaction.id) else { return false }
            guard old.updatedAt == expectedUpdatedAt, transaction.updatedAt >= old.updatedAt,
                  transaction.createdAt == old.createdAt, transaction.requestKey == old.requestKey,
                  transaction.source == old.source, transaction.sourceID == old.sourceID,
                  transaction.deletedAt == old.deletedAt else { throw LedgerError.conflict }
            try Self.validateCurrencies(db, transaction: transaction)
            try TransactionRecord(transaction).update(db)
            try Self.replaceTags(db, transaction: transaction)
            return true
        }
    }

    func transaction(id: String) async throws -> LedgerTransaction? {
        try await read { db in try Self.find(db, id: id) }
    }
    func transaction(requestKey: String) async throws -> LedgerTransaction? {
        try await read { db in try Self.load(db, sql: "SELECT * FROM transactions WHERE request_key = ?", arguments: [requestKey]).first }
    }
    func recentTransactions(limit: Int = 200) async throws -> [LedgerTransaction] {
        guard (1...2000).contains(limit) else { throw LedgerError.invalidField("limit") }
        return try await read { db in
            try Self.load(db, sql: "SELECT * FROM transactions WHERE deleted_at_epoch_millis IS NULL ORDER BY occurred_at_epoch_millis DESC, id DESC LIMIT ?", arguments: [limit])
        }
    }
    func transactions(startEpochDay: Int64, endEpochDayExclusive: Int64, limit: Int = 200) async throws -> [LedgerTransaction] {
        guard startEpochDay < endEpochDayExclusive, (1...2000).contains(limit) else { throw LedgerError.invalidField("range") }
        return try await read { db in
            try Self.load(db, sql: "SELECT * FROM transactions WHERE deleted_at_epoch_millis IS NULL AND occurred_local_epoch_day >= ? AND occurred_local_epoch_day < ? ORDER BY occurred_at_epoch_millis DESC, id DESC LIMIT ?",
                          arguments: [startEpochDay, endEpochDayExclusive, limit])
        }
    }

    func observeRecentTransactions(limit: Int = 200) -> AsyncThrowingStream<[LedgerTransaction], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard (1...2000).contains(limit) else { throw LedgerError.invalidField("limit") }
                    let observation = ValueObservation.tracking { db in
                        try Self.load(db, sql: "SELECT * FROM transactions WHERE deleted_at_epoch_millis IS NULL ORDER BY occurred_at_epoch_millis DESC, id DESC LIMIT ?", arguments: [limit])
                    }
                    for try await values in observation.values(in: database.writer) {
                        guard !Task.isCancelled else { break }
                        continuation.yield(values)
                    }
                    continuation.finish()
                } catch let error as DatabaseError { continuation.finish(throwing: Self.storageError(error)) }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func softDeleteTransaction(id: String, at timestamp: Int64) async throws -> Bool {
        try await write { db in
            try Self.checkManaged(db, id: id)
            try db.execute(sql: "UPDATE transactions SET deleted_at_epoch_millis = ?, updated_at_epoch_millis = ? WHERE id = ? AND deleted_at_epoch_millis IS NULL AND updated_at_epoch_millis <= ?",
                           arguments: [timestamp, timestamp, id, timestamp])
            return db.changesCount > 0
        }
    }
    func restoreTransaction(id: String, at timestamp: Int64) async throws -> Bool {
        try await write { db in
            try Self.checkManaged(db, id: id)
            try db.execute(sql: "UPDATE transactions SET deleted_at_epoch_millis = NULL, updated_at_epoch_millis = ? WHERE id = ? AND deleted_at_epoch_millis IS NOT NULL AND updated_at_epoch_millis <= ?",
                           arguments: [timestamp, id, timestamp])
            return db.changesCount > 0
        }
    }

    private static func requireAsset(_ db: Database, _ code: CurrencyCode, type: AssetType) throws {
        guard try CurrencyRecord.fetchOne(db, key: code.rawValue)?.asset_type == type.rawValue else { throw LedgerError.invalidCurrencyType }
    }
    func saveFiatQuote(_ quote: FiatQuote) async throws {
        try quote.validate()
        try await write { db in
            try Self.requireAsset(db, quote.original, type: .fiat)
            try Self.requireAsset(db, quote.base, type: .fiat)
            try FiatQuoteRecord(quote).save(db)
        }
    }
    func latestFiatQuote(original: CurrencyCode, base: CurrencyCode, providerID: String) async throws -> FiatQuote? {
        try await read { db in
            try FiatQuoteRecord.fetchOne(db, sql: "SELECT * FROM fx_quotes WHERE original_currency_code = ? AND base_currency_code = ? AND provider_id = ? AND quote_kind = 'LATEST' ORDER BY rate_data_timestamp DESC LIMIT 1",
                                        arguments: [original.rawValue, base.rawValue, providerID])?.model()
        }
    }
    func historicalFiatQuote(original: CurrencyCode, base: CurrencyCode, providerID: String, epochDay: Int64) async throws -> FiatQuote? {
        try await read { db in
            try FiatQuoteRecord.fetchOne(db, sql: "SELECT * FROM fx_quotes WHERE original_currency_code = ? AND base_currency_code = ? AND provider_id = ? AND quote_kind = 'HISTORICAL' AND rate_date_epoch_day = ? ORDER BY rate_data_timestamp DESC LIMIT 1",
                                        arguments: [original.rawValue, base.rawValue, providerID, epochDay])?.model()
        }
    }
    func saveMarketQuote(_ quote: MarketQuote) async throws {
        try quote.validate()
        try await write { db in
            try Self.requireAsset(db, quote.asset, type: .crypto)
            try Self.requireAsset(db, quote.base, type: .fiat)
            try MarketQuoteRecord(quote).save(db)
        }
    }
    func marketQuote(asset: CurrencyCode, base: CurrencyCode, providerID: String) async throws -> MarketQuote? {
        try await read { db in
            try MarketQuoteRecord.fetchOne(db, sql: "SELECT * FROM crypto_price_quotes WHERE asset_code = ? AND base_code = ? AND provider_id = ?",
                                          arguments: [asset.rawValue, base.rawValue, providerID])?.model()
        }
    }
}
