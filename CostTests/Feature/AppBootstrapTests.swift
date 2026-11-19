import Testing
import Foundation
@testable import Cost

private actor DatabaseFactoryFixture {
    let database: AppDatabase
    private(set) var calls = 0
    init(_ database: AppDatabase) { self.database = database }
    func open() -> AppDatabase { calls += 1; return database }
}

struct AppBootstrapTests {
    @Test @MainActor
    func databaseIsAssembledOnceAndInjectedAsDomainProtocols() async throws {
        let fixture = DatabaseFactoryFixture(try AppDatabase.inMemory())
        let container = AppContainer(mediaRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), openDatabase: { await fixture.open() })
        await container.start()
        await container.start()
        #expect(container.isReady && !container.isLoading && !container.startupFailed)
        #expect(await fixture.calls == 1)
        let repositories = try #require(container.repositories)
        #expect(try await repositories.currencies.currencies(includeDisabled: true).count == 15)
        #expect(try await repositories.transactions.recentTransactions(limit: 200).isEmpty)
    }

    @Test @MainActor
    func databaseFailureIsNotReportedAsReady() async {
        let container = AppContainer(openDatabase: { throw LedgerError.storageUnavailable })
        await container.start()
        #expect(container.startupFailed && !container.isReady && !container.isLoading)
        #expect(container.repositories == nil)
    }

    @Test @MainActor
    func foregroundActivationProcessesPersistedRulesAndReloadsLedger() async throws {
        let database = try AppDatabase.inMemory()
        let repositories = LedgerRepositories(database: database)
        let schedule = RecurringSchedule(startDay: 1, endDay: 2, minutes: 60, zoneID: "UTC")
        let content = try RecurringContent(name: "fixture", type: .expense,
            amount: Money.parse("12.34", currencyCode: CurrencyCode("CNY"), scale: 2), categoryID: "seed-expense-other",
            accountID: "seed-default-account", note: nil, tagIDs: [], schedule: schedule, catchUp: .createMissed)
        try await repositories.recurring.saveRecurringRule(id: "foreground", content: content, expectedVersion: nil, at: 1000)
        let fixture = DatabaseFactoryFixture(database)
        let container = AppContainer(mediaRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            recurringEnvironment: LedgerEnvironment(now: { 3 * 86_400_000 }), openDatabase: { await fixture.open() })
        await container.processRecurring()
        #expect(container.ledger?.rows.count == 2)
        #expect(Set(container.ledger?.rows.map(\.occurredAt.localEpochDay) ?? []) == [1, 2])
        await container.processRecurring()
        #expect(container.ledger?.rows.count == 2)
        #expect(await fixture.calls == 1)
    }

    @Test @MainActor
    func backgroundEntryUsesTheRegisteredRefreshIdentifierAndSameLedger() async throws {
        let identifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(identifiers == [RecurringSystem.refreshIdentifier])
        #expect(modes?.contains("fetch") == true)

        let database = try AppDatabase.inMemory()
        let repositories = LedgerRepositories(database: database)
        let content = try RecurringContent(name: "fixture", type: .expense,
            amount: Money.parse("1", currencyCode: CurrencyCode("CNY"), scale: 2), categoryID: "seed-expense-other",
            accountID: "seed-default-account", note: nil, tagIDs: [],
            schedule: RecurringSchedule(startDay: 1, endDay: 1, minutes: 0, zoneID: "UTC"), catchUp: .createMissed)
        try await repositories.recurring.saveRecurringRule(id: "background", content: content, expectedVersion: nil, at: 1000)
        let container = AppContainer(mediaRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            recurringEnvironment: LedgerEnvironment(now: { 2 * 86_400_000 }), openDatabase: { database })
        await container.processRecurring(background: true)
        #expect(try await repositories.transactions.recentTransactions(limit: 10).count == 1)
        await container.processRecurring()
        #expect(container.ledger?.rows.count == 1)
    }
}
