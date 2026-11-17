import Observation

/// Composition root; feature ViewModels receive individual Domain protocols, not SQL objects.
@MainActor
@Observable
final class AppContainer {
    @ObservationIgnored private let openDatabase: @Sendable () async throws -> AppDatabase
    @ObservationIgnored private(set) var repositories: LedgerRepositories?
    private(set) var isLoading = false
    private(set) var isReady = false
    private(set) var ledger: LedgerViewModel?
    var startupFailed = false

    init(openDatabase: @escaping @Sendable () async throws -> AppDatabase = { try await AppDatabase.openDefault() }) {
        self.openDatabase = openDatabase
    }

    func start() async {
        guard !isLoading && !isReady else { return }
        isLoading = true
        startupFailed = false
        defer { isLoading = false }
        do {
            let database = try await openDatabase()
            let repositories = LedgerRepositories(database: database)
            self.repositories = repositories
            ledger = LedgerViewModel(services: LedgerServices(currencies: repositories.currencies, categories: repositories.categories,
                accounts: repositories.accounts, tags: repositories.tags, transactions: repositories.transactions,
                funds: repositories.funds, drafts: PrivateEntryDraftStore()))
            isReady = true
        } catch {
            // SQL errors may include bound financial values. Never log/display their raw description.
            repositories = nil
            ledger = nil
            startupFailed = true
        }
    }
}
