import Foundation

enum CategoryDeletionResult: Equatable, Sendable { case deleted, notFound, notArchived, hasChildren, inUse }

protocol CurrencyRepository: Sendable {
    func currencies(includeDisabled: Bool) async throws -> [Currency]
    func currency(code: CurrencyCode) async throws -> Currency?
    func saveCurrency(_ currency: Currency) async throws
}

protocol CategoryRepository: Sendable {
    func categories(includeArchived: Bool) async throws -> [Category]
    func category(id: String) async throws -> Category?
    func saveCategory(_ category: Category) async throws
    func installBuiltInCategories() async throws -> Int
    func archiveCategory(id: String, at timestamp: Int64) async throws
    func deleteArchivedCategory(id: String) async throws -> CategoryDeletionResult
}

protocol AccountRepository: Sendable {
    func accounts(includeArchived: Bool) async throws -> [Account]
    func account(id: String) async throws -> Account?
    func saveAccount(_ account: Account) async throws
}

protocol TagRepository: Sendable {
    func tags(includeArchived: Bool) async throws -> [Tag]
    func tag(id: String) async throws -> Tag?
    func saveTag(_ tag: Tag) async throws -> Tag
    func deleteArchivedTag(id: String) async throws -> Bool
}

protocol TransactionRepository: Sendable {
    func searchTransactions(_ query: LedgerQuery) async throws -> LedgerPage
    func isManagedTransaction(id: String) async throws -> Bool
    /// The serialized transaction boundary returns an existing request instead of writing twice.
    func createTransaction(_ transaction: LedgerTransaction) async throws -> LedgerTransaction
    func updateTransaction(_ transaction: LedgerTransaction, expectedUpdatedAt: Int64) async throws -> Bool
    func transaction(id: String) async throws -> LedgerTransaction?
    func transaction(requestKey: String) async throws -> LedgerTransaction?
    func recentTransactions(limit: Int) async throws -> [LedgerTransaction]
    func transactions(startEpochDay: Int64, endEpochDayExclusive: Int64, limit: Int) async throws -> [LedgerTransaction]
    func observeRecentTransactions(limit: Int) -> AsyncThrowingStream<[LedgerTransaction], Error>
    func softDeleteTransaction(id: String, at timestamp: Int64) async throws -> Bool
    func restoreTransaction(id: String, at timestamp: Int64) async throws -> Bool
}

protocol FiatQuoteRepository: Sendable {
    func saveFiatQuote(_ quote: FiatQuote) async throws
    func latestFiatQuote(original: CurrencyCode, base: CurrencyCode, providerID: String) async throws -> FiatQuote?
    func historicalFiatQuote(original: CurrencyCode, base: CurrencyCode, providerID: String, epochDay: Int64) async throws -> FiatQuote?
}

protocol MarketQuoteRepository: Sendable {
    func saveMarketQuote(_ quote: MarketQuote) async throws
    func marketQuote(asset: CurrencyCode, base: CurrencyCode, providerID: String) async throws -> MarketQuote?
}
