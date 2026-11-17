import Observation
import Foundation

/// Composition root; feature ViewModels receive individual Domain protocols, not SQL objects.
@MainActor
@Observable
final class AppContainer {
    @ObservationIgnored private let openDatabase: @Sendable () async throws -> AppDatabase
    @ObservationIgnored private let configuredMediaRoot: URL?
    @ObservationIgnored private(set) var repositories: LedgerRepositories?
    private(set) var isLoading = false
    private(set) var isReady = false
    private(set) var ledger: LedgerViewModel?
    var startupFailed = false

    init(mediaRoot: URL? = nil, openDatabase: @escaping @Sendable () async throws -> AppDatabase = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--cost-ui-testing") { return try AppDatabase.inMemory() }
        #endif
        return try await AppDatabase.openDefault()
    }) {
        self.openDatabase = openDatabase
        configuredMediaRoot = mediaRoot
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
            var mediaRoot = try configuredMediaRoot ?? ManagedVisualStore.defaultRoot()
            var draftSuite: String?
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--cost-ui-testing") {
                let testID = UUID().uuidString
                mediaRoot = FileManager.default.temporaryDirectory.appendingPathComponent("CostUITesting-\(testID)")
                draftSuite = "cost-ui-testing-\(testID)"
            }
            #endif
            let visuals = ManagedVisualStore(database: database, root: mediaRoot)
            try await visuals.cleanup()
            ledger = LedgerViewModel(services: LedgerServices(currencies: repositories.currencies, categories: repositories.categories,
                accounts: repositories.accounts, tags: repositories.tags, transactions: repositories.transactions,
                funds: repositories.funds, drafts: PrivateEntryDraftStore(suiteName: draftSuite),
                visuals: visuals))
            isReady = true
        } catch {
            // SQL errors may include bound financial values. Never log/display their raw description.
            repositories = nil
            ledger = nil
            startupFailed = true
        }
    }
}
