import Foundation
import GRDB
import Testing
@testable import Cost

struct RecurringRepositoryTests {
    private static let day: Int64 = 86_400_000
    private static let today: Int64 = 20_800
    private static let now = today * day + 43_200_000

    @Test func simultaneousExecutionAndRestartKeepOneFrozenBill() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.sqlite")
        var content = try makeContent(start: Self.today, end: Self.today)
        let tag = TestLedger.tag()
        content.tagIDs = [tag.id]
        do {
            let repo = GRDBLedgerRepository(database: try await AppDatabase.open(at: url))
            _ = try await repo.saveTag(tag)
            try await repo.saveRecurringRule(id: "one", content: content, expectedVersion: nil, at: Self.now)
            async let foreground: Void = drain(process(repo))
            async let background: Void = drain(process(repo))
            _ = try await (foreground, background)
        }
        let db = try await AppDatabase.open(at: url)
        let reopened = GRDBLedgerRepository(database: db)
        try await drain(process(reopened))
        let rules = try await reopened.recurringRules()
        let next = try #require(rules.first)
        #expect(next.nextOccurrence == nil)
        let bills = try await reopened.recentTransactions(limit: 10)
        let bill = try #require(bills.first)
        #expect(bills.count == 1)
        #expect(bill.source == .recurring && bill.sourceID == "one")
        #expect(bill.occurredAt.epochMillis == Self.today * Self.day)
        #expect(bill.createdAt == Self.now)
        #expect(bill.tagIDs == [tag.id])
        #expect(bill.original == content.amount && bill.original == bill.convertedBase)
        try await reopened.deleteRecurringRule(next)
        #expect(try await reopened.recurringRules().isEmpty)
        #expect(try await reopened.transaction(id: bill.id) == bill)
        let count = try await db.writer.read { try RecurringExecutionRecord.fetchCount($0) }
        #expect(count == 0)
    }

    @Test func pauseAndResumeChooseWhetherToBackfillEarlierBusinessDays() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let content = try makeContent(start: Self.today - 2, end: Self.today)
        for id in ["older", "today"] {
            try await repo.saveRecurringRule(id: id, content: content, expectedVersion: nil, at: Self.now - 3 * Self.day)
        }
        for rule in try await repo.recurringRules() {
            try await repo.setRecurringEnabled(rule, enabled: false, catchUp: .createMissed, at: Self.now - 3 * Self.day)
        }
        try await drain(process(repo))
        #expect(try await repo.recentTransactions(limit: 10).isEmpty)
        for rule in try await repo.recurringRules() {
            try await repo.setRecurringEnabled(rule, enabled: true, catchUp: rule.id == "older" ? .createMissed : .skipMissed, at: Self.now)
        }
        try await drain(process(repo))
        let bills = try await repo.recentTransactions(limit: 10)
        #expect(bills.filter { $0.sourceID == "older" }.count == 3)
        #expect(bills.filter { $0.sourceID == "today" }.map(\.occurredAt.localEpochDay) == [Self.today])
    }

    @Test func writeFailureRollsBackBillTagsExecutionAndCursor() async throws {
        let db = try AppDatabase.inMemory()
        let repo = GRDBLedgerRepository(database: db)
        let content = try makeContent(start: Self.today, end: Self.today)
        try await repo.saveRecurringRule(id: "rollback", content: content, expectedVersion: nil, at: Self.now)
        try await db.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER fixture_failure BEFORE INSERT ON recurring_executions BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        }
        await #expect(throws: LedgerError.storageConstraint) { try await drain(process(repo)) }
        #expect(try await repo.recentTransactions(limit: 10).isEmpty)
        #expect(try await repo.recurringRules().first?.nextOccurrence == Self.today * Self.day)
        try await db.writer.write { try $0.execute(sql: "DROP TRIGGER fixture_failure") }
        try await drain(process(repo))
        #expect(try await repo.recentTransactions(limit: 10).count == 1)
    }

    @Test func cancellationWhileObtainingValuationLeavesWorkAvailable() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        try await repo.saveRecurringRule(id: "cancel", content: makeContent(start: Self.today, end: Self.today, code: "USD"),
            expectedVersion: nil, at: Self.now)
        let provider = SuspendedRecurringProvider()
        let task = Task { try await drain(process(repo, provider: provider)) }
        await provider.waitUntilStarted()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await repo.recurringFailures(limit: 10, after: nil).isEmpty)
        #expect(try await repo.recurringRules().first?.nextOccurrence == Self.today * Self.day)
        try await drain(process(repo, provider: fixtureQuote()))
        #expect(try await repo.recentTransactions(limit: 10).count == 1)
    }

    @Test func unavailableValuationDoesNotBlockOtherRulesAndCanBeRetriedOrSkipped() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let usd = try makeContent(start: Self.today - 1, end: Self.today, code: "USD")
        let cny = try makeContent(start: Self.today, end: Self.today)
        try await repo.saveRecurringRule(id: "usd", content: usd, expectedVersion: nil, at: Self.now)
        try await repo.saveRecurringRule(id: "cny", content: cny, expectedVersion: nil, at: Self.now)
        try await drain(process(repo))
        #expect(try await repo.recentTransactions(limit: 10).map(\.sourceID) == ["cny"])
        let failures = try await repo.recurringFailures(limit: 10, after: nil)
        let failed = try #require(failures.first)
        #expect(failed.issue == .valuationUnavailable && failed.attempts == 1)
        let processor = process(repo, provider: try fixtureQuote())
        #expect(try await processor.resolve(failed, skipping: false) == .created)
        try await drain(process(repo))
        let remaining = try await repo.recurringFailures(limit: 10, after: nil)
        let next = try #require(remaining.first)
        #expect(try await processor.resolve(next, skipping: true) == .skipped)
        let bills = try await repo.recentTransactions(limit: 10)
        let foreign = try #require(bills.first { $0.sourceID == "usd" })
        #expect(foreign.exchangeRate.method == .historical)
        #expect(foreign.exchangeRate.providerID == "fixture" && foreign.exchangeRate.rate.text == "7.25")
        #expect(foreign.convertedBase.minorUnits == 8946 && foreign.original == usd.amount)
        #expect(foreign.occurredAt.localEpochDay == Self.today - 1)
        #expect(try await repo.recurringFailures(limit: 10, after: nil).isEmpty)
    }

    @Test func latestQuoteMustBeFreshAndRemindersDoNotDependOnProcessing() async throws {
        let repo = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        let content = try makeContent(start: Self.today - 1, end: Self.today + 2, code: "USD")
        try await repo.saveRecurringRule(id: "future", content: content, expectedVersion: nil, at: Self.now)
        let rows = try await repo.recurringRules()
        let reminders = try RecurringReminder.upcoming(rules: rows, after: Self.now, limit: 32)
        #expect(reminders.map(\.instant) == [Self.today + 1, Self.today + 2].map { $0 * Self.day })
        let rule = try #require(rows.first)
        try await repo.setRecurringEnabled(rule, enabled: false, catchUp: .skipMissed, at: Self.now)
        let pausedRows = try await repo.recurringRules()
        #expect(try RecurringReminder.upcoming(rules: pausedRows, after: Self.now, limit: 32).isEmpty)
        let paused = try #require(pausedRows.first)
        try await repo.setRecurringEnabled(paused, enabled: true, catchUp: .skipMissed, at: Self.now)

        try await drain(process(repo, provider: fixtureQuote(age: 300_000)))
        let failures = try await repo.recurringFailures(limit: 10, after: nil)
        let failed = try #require(failures.first)
        #expect(failed.issue == .staleQuote)
        #expect(try await repo.recentTransactions(limit: 10).isEmpty)
        #expect(try await process(repo, provider: fixtureQuote(age: 299_999)).resolve(failed, skipping: false) == .created)
        let bills = try await repo.recentTransactions(limit: 10)
        let foreign = try #require(bills.first)
        #expect(foreign.exchangeRate.method == .latest && foreign.exchangeRate.dataTimestamp == Self.now - 299_999)
    }

    private func makeContent(start: Int64, end: Int64, code: String = "CNY") throws -> RecurringContent {
        RecurringContent(name: "fixture", type: .expense, amount: try Money.parse("12.34", currencyCode: CurrencyCode(code), scale: 2),
            categoryID: "seed-expense-other", accountID: "seed-default-account", note: "fixture", tagIDs: [],
            schedule: RecurringSchedule(startDay: start, endDay: end, minutes: 0, zoneID: "UTC"), catchUp: .createMissed)
    }

    private func process(_ repo: GRDBLedgerRepository, provider: any RecurringFiatProvider = UnconfiguredRecurringFiatProvider()) -> ProcessRecurringRules {
        ProcessRecurringRules(rules: repo, currencies: repo, provider: provider, environment: LedgerEnvironment(now: { Self.now }))
    }

    private func drain(_ processor: ProcessRecurringRules) async throws {
        var blocked: Set<String> = []
        _ = try await processor.runDue(excluding: &blocked)
    }

    private func fixtureQuote(age: Int64 = 1000) throws -> RecurringQuoteFixture {
        RecurringQuoteFixture(now: Self.now, data: Self.now - age, rate: try DecimalRate("7.25"))
    }
}

private struct RecurringQuoteFixture: RecurringFiatProvider {
    let now: Int64
    let data: Int64
    let rate: DecimalRate

    func latest(original: CurrencyCode, base: CurrencyCode) async throws -> FiatQuote {
        FiatQuote(id: "latest", original: original, base: base, rate: rate, providerID: "fixture", dataTimestamp: data,
            rateEpochDay: nil, fetchedAt: now, expiresAt: data + 300_000, kind: .latest)
    }

    func historical(original: CurrencyCode, base: CurrencyCode, epochDay: Int64) async throws -> FiatQuote {
        FiatQuote(id: "historical", original: original, base: base, rate: rate, providerID: "fixture", dataTimestamp: data,
            rateEpochDay: epochDay, fetchedAt: now, expiresAt: now, kind: .historical)
    }
}

private actor SuspendedRecurringProvider: RecurringFiatProvider {
    private var started = false

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func latest(original: CurrencyCode, base: CurrencyCode) async throws -> FiatQuote {
        started = true
        try await Task.sleep(for: .seconds(10))
        throw RecurringIssue.valuationUnavailable
    }

    func historical(original: CurrencyCode, base: CurrencyCode, epochDay: Int64) async throws -> FiatQuote {
        try await latest(original: original, base: base)
    }
}
