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
}
