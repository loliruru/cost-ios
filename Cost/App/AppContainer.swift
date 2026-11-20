import Observation
import Foundation

/// Composition root; feature ViewModels receive individual Domain protocols, not SQL objects.
@MainActor
@Observable
final class AppContainer {
    @ObservationIgnored private let openDatabase: @Sendable () async throws -> AppDatabase
    @ObservationIgnored private let configuredMediaRoot: URL?
    @ObservationIgnored private let recurringEnvironment: LedgerEnvironment
    @ObservationIgnored private var startup: Task<Void, Never>?
    @ObservationIgnored private(set) var repositories: LedgerRepositories?
    private(set) var isLoading = false
    private(set) var isReady = false
    private(set) var ledger: LedgerViewModel?
    private(set) var recurring: RecurringViewModel?
    private(set) var statistics: StatisticsViewModel?
    var startupFailed = false

    init(mediaRoot: URL? = nil, recurringEnvironment: LedgerEnvironment = LedgerEnvironment(),
         openDatabase: @escaping @Sendable () async throws -> AppDatabase = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--cost-ui-testing") { return try AppDatabase.inMemory() }
        #endif
        return try await AppDatabase.openDefault()
    }) {
        self.openDatabase = openDatabase
        configuredMediaRoot = mediaRoot
        self.recurringEnvironment = recurringEnvironment
    }

    func start() async {
        guard !isReady else { return }
        if let startup { await startup.value; return }
        let task = Task { await open() }
        startup = task
        await task.value
    }

    private func open() async {
        isLoading = true
        startupFailed = false
        defer { isLoading = false; startup = nil }
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
            let ledger = LedgerViewModel(services: LedgerServices(currencies: repositories.currencies, categories: repositories.categories,
                accounts: repositories.accounts, tags: repositories.tags, transactions: repositories.transactions,
                funds: repositories.funds, drafts: PrivateEntryDraftStore(suiteName: draftSuite),
                visuals: visuals, templates: repositories.templates))
            self.ledger = ledger
            recurring = RecurringViewModel(ledger: ledger, rules: repositories.recurring, system: RecurringSystem(), environment: recurringEnvironment)
            statistics = try StatisticsViewModel(repository: repositories.statistics, anomalies: repositories.anomalies,
                preferenceStore: PrivateAnomalyPreferences(suiteName: draftSuite),
                currency: CurrencyCode(EntryDraft.defaultBaseCurrencyCode), environment: recurringEnvironment)
            isReady = true
        } catch {
            // SQL errors may include bound financial values. Never log/display their raw description.
            repositories = nil
            ledger = nil
            recurring = nil
            statistics = nil
            startupFailed = true
        }
    }

    func processRecurring(background: Bool = false) async {
        await start()
        guard !Task.isCancelled, let recurring else { return }
        if background { recurring.rearmBackgroundRefresh() }
        await recurring.run(background: background)
    }
}
