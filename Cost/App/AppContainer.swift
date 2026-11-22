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
    private(set) var portable: PortableDataViewModel?
    private(set) var restoredTheme: String?
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
            let preferences = try PortableSettingsStore(root: mediaRoot, suiteName: draftSuite)
            let maintenance = LedgerMaintenance()
            let recurringSystem = RecurringSystem()
            let credentials: any QuoteCredentials
            #if DEBUG
            if draftSuite != nil { credentials = UITestQuoteCredentials() }
            else { credentials = KeychainQuoteCredentials() }
            #else
            credentials = KeychainQuoteCredentials()
            #endif
            let defaultsDomain = draftSuite ?? Bundle.main.bundleIdentifier
            let transfer = LocalPortableDataRepository(database: database, visuals: visuals, settings: preferences,
                maintenance: maintenance, root: mediaRoot.appendingPathComponent("data-transfer", isDirectory: true),
                clearPrivateState: {
                    try await credentials.setAPIKey(nil)
                    await recurringSystem.resetLocalData()
                    if let defaultsDomain { UserDefaults.standard.removePersistentDomain(forName: defaultsDomain) }
                })
            try await transfer.clearAbandonedStages()
            try await transfer.finishPendingMaintenance()
            restoredTheme = await preferences.snapshot().theme_mode
            let repositories = LedgerRepositories(database: database)
            self.repositories = repositories
            let base = try await preferredBaseCurrency(preferences, in: repositories.currencies)
            let provider = TwelveDataQuotes(credentials: credentials, transport: TwelveDataTransport(), now: recurringEnvironment.now)
            let quotes = QuoteServices(credentials: credentials, fiatProvider: provider, marketProvider: provider,
                fiatCache: repositories.fiatQuotes, marketCache: repositories.marketQuotes, now: recurringEnvironment.now)
            try await visuals.cleanup()
            #if DEBUG
            if draftSuite != nil, ProcessInfo.processInfo.arguments.contains("--cost-anomaly-fixture") {
                try await seedAnomalyFixture(in: repositories.transactions)
            }
            #endif
            let ledger = LedgerViewModel(services: LedgerServices(currencies: repositories.currencies, categories: repositories.categories,
                accounts: repositories.accounts, tags: repositories.tags, transactions: repositories.transactions,
                funds: repositories.funds, drafts: PrivateEntryDraftStore(suiteName: draftSuite),
                visuals: visuals, templates: repositories.templates, quotes: quotes, credentials: credentials,
                basePreferences: preferences), environment: recurringEnvironment, baseCurrency: base)
            self.ledger = ledger
            recurring = RecurringViewModel(ledger: ledger, rules: repositories.recurring, system: recurringSystem,
                environment: recurringEnvironment, maintenance: maintenance, recoverSettings: { try await transfer.finishPendingMaintenance() })
            let coverage = PrivateRecordingCoverageStore(suiteName: draftSuite)
            let makeStatistics: @MainActor (CurrencyCode) -> StatisticsViewModel = { [recurringEnvironment] currency in
                StatisticsViewModel(repository: repositories.statistics, anomalies: repositories.anomalies,
                    preferenceStore: preferences, coverageStore: coverage, currency: currency, environment: recurringEnvironment)
            }
            statistics = makeStatistics(base.code)
            portable = PortableDataViewModel(repository: transfer, onImport: { [weak self] kind, outcome in
                guard let self else { return }
                if kind == .backup {
                    if !outcome.settingsPending { self.restoredTheme = await preferences.snapshot().theme_mode }
                    await self.ledger?.refreshAfterRestore()
                    await self.statistics?.refreshAfterRestore()
                    await self.recurring?.refreshAfterRestore()
                } else {
                    await self.ledger?.reload()
                }
            }, onReset: { [weak self] in
                guard let self else { return }
                self.restoredTheme = nil
                await self.ledger?.refreshAfterRestore()
                if let code = self.ledger?.baseCurrency?.code { self.statistics = makeStatistics(code) }
                await self.recurring?.refreshAfterReset()
            })
            isReady = true
        } catch {
            // SQL errors may include bound financial values. Never log/display their raw description.
            repositories = nil
            ledger = nil
            recurring = nil
            statistics = nil
            portable = nil
            startupFailed = true
        }
    }

    func processRecurring(background: Bool = false) async {
        await start()
        guard !Task.isCancelled, let recurring else { return }
        if background { recurring.rearmBackgroundRefresh() }
        await recurring.run(background: background)
    }

    #if DEBUG
    private func seedAnomalyFixture(in repository: any TransactionRepository) async throws {
        let now = recurringEnvironment.now()
        let today = try OccurredAt(epochMillis: now, zoneID: recurringEnvironment.zoneID()).localEpochDay
        let code = try CurrencyCode(EntryDraft.defaultBaseCurrencyCode)
        for day in Array((today - 15)...(today - 11)) + [today - 1, today] {
            let amount = try Money(minorUnits: day == today ? 500 : 100, currencyCode: code, scale: 2)
            let row = try LedgerTransaction(id: "anomaly-fixture-\(day)", type: .expense, original: amount,
                convertedBase: amount, exchangeRate: .identity(), categoryID: "seed-expense-other",
                accountID: "seed-default-account", occurredAt: OccurredAt(epochMillis: day * 86_400_000, zoneID: "UTC"),
                note: nil, source: .manual, sourceID: nil, requestKey: nil, createdAt: now, updatedAt: now,
                deletedAt: nil, tagIDs: [])
            _ = try await repository.createTransaction(row)
        }
    }
    #endif
}

#if DEBUG
private actor UITestQuoteCredentials: QuoteCredentials {
    private var key: String?
    func apiKey() -> String? { key }
    func setAPIKey(_ key: String?) { self.key = key }
}
#endif
