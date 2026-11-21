import Foundation
import Testing
@testable import Cost

struct SpendingFrequencyTests {
    @Test func unknownDaysAndTodayAreAbsentFromBothCounts() throws {
        let range = SpendingFrequencyRange(today: 100, window: .week)
        let original = SpendingFrequency(range: range, coverage: RecordingCoverage(), expenseDays: [93, 99, 100])
        #expect(original.recent.coveredDays == 0)
        #expect(original.recent.spendingDays == 0)
        #expect(original.recent.basisPoints == nil)
        #expect(original.issues == [.unconfirmed])

        var coverage = RecordingCoverage()
        try coverage.apply(.start(90), today: 92)
        try coverage.apply(.pause, today: 94)
        try coverage.apply(.resume, today: 96)
        try coverage.apply(.markUnknown(93), today: 100)
        try coverage.apply(.confirmDay(95), today: 100)
        let result = SpendingFrequency(range: range, coverage: coverage, expenseDays: [93, 95, 96, 98, 100])
        #expect(result.recent.days == 93..<100)
        #expect(result.recent.coveredDays == 4)
        #expect(result.recent.spendingDays == 2)
        #expect(result.recent.basisPoints == DecimalInteger("5000"))
        #expect(result.issues == [.tooFewRecent(required: 5), .tooFewHistorical])

        let followingDay = SpendingFrequencyRange(today: 101, window: .week)
        let following = SpendingFrequency(range: followingDay, coverage: coverage, expenseDays: [93, 95, 96, 98, 100])
        #expect(following.recent.days == 94..<101)
        #expect(following.recent.coveredDays == 5)
        #expect(following.recent.spendingDays == 3)
    }

    @Test func bothFixedWindowsEndAtThePreviousCompletedDay() throws {
        let today = GregorianDay(year: 2026, month: 11, day: 23).epochDay
        let monday = GregorianDay(year: 2026, month: 11, day: 16).epochDay
        let startsMonth = GregorianDay(year: 2026, month: 10, day: 24).epochDay
        var coverage = RecordingCoverage()
        try coverage.apply(.start(monday - 100), today: today)
        let week = SpendingFrequency(range: SpendingFrequencyRange(today: today, window: .week),
            coverage: coverage, expenseDays: [monday, today - 1, today, today + 1])
        #expect(week.recent.days == monday..<today)
        #expect(week.recent.coveredDays == 7)
        #expect(week.recent.spendingDays == 2)
        #expect(week.recent.basisPoints == DecimalInteger("2857"))
        #expect(week.history.days == (monday - 30)..<monday)
        #expect(week.issues.isEmpty)

        let month = SpendingFrequency(range: SpendingFrequencyRange(today: today, window: .month),
            coverage: coverage, expenseDays: [startsMonth, today - 1, today])
        #expect(month.recent.days == startsMonth..<today)
        #expect(month.recent.coveredDays == 30)
        #expect(month.recent.spendingDays == 2)
    }

    @Test func historyExtendsWhenTheShortWindowLacksWeekdayCoverage() throws {
        let range = SpendingFrequencyRange(today: 100, window: .week)
        var coverage = RecordingCoverage()
        try coverage.apply(.start(0), today: 100)
        try coverage.apply(.markUnknown(86), today: 100)
        try coverage.apply(.markUnknown(79), today: 100)
        let result = SpendingFrequency(range: range, coverage: coverage, expenseDays: [50, 79, 86, 99])
        #expect(result.history.days == 3..<93)
        #expect(result.history.coveredDays == 88)
        #expect(result.history.spendingDays == 1)
        #expect(result.issues.isEmpty)
    }

    @Test func explicitCoveragePersistsAndTodayRequiresCompletion() async throws {
        let suite = "coverage-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = PrivateRecordingCoverageStore(suiteName: suite)
        var coverage = try await store.load()
        #expect(!coverage.hasCoverageDeclaration)
        try coverage.apply(.start(87), today: 100)
        try coverage.apply(.pause, today: 100)
        try coverage.apply(.markUnknown(90), today: 100)
        try coverage.apply(.confirmDay(78), today: 100)
        #expect(throws: LedgerError.invalidField("coverageDay")) {
            try coverage.apply(.confirmDay(100), today: 100)
        }
        try await store.save(coverage)
        let reloaded = try await PrivateRecordingCoverageStore(suiteName: suite).load()
        #expect(reloaded == coverage)
        #expect(reloaded.activeStart == nil)
        #expect(reloaded.contains(78))
        #expect(!reloaded.contains(90))
        #expect(reloaded.contains(99))
        #expect(!reloaded.contains(100))
    }

    @Test @MainActor func viewModelUsesRefreshedBusinessDayForBothWindows() async throws {
        let clock = TestFrequencyClock(1_795_276_799_000)
        let model = try makeModel(clock, zone: "Asia/Singapore")
        await model.loadPreferences()
        let nov21 = GregorianDay(year: 2026, month: 11, day: 21).epochDay
        #expect(model.today == nov21)
        #expect(model.frequencyQuery?.range.recent == (nov21 - 7)..<nov21)
        #expect(model.detectionQuery?.request.today == nov21)

        clock.set(1_795_276_800_000)
        model.refreshDay()
        #expect(model.today == nov21 + 1)
        #expect(model.frequencyQuery?.range.recent == (nov21 - 6)..<(nov21 + 1))
        #expect(model.detectionQuery?.request.today == nov21 + 1)
    }

    @Test @MainActor func aRepeatedDSTHourDoesNotAdvanceTheBusinessDay() throws {
        let clock = TestFrequencyClock(1_793_511_000_000)
        let model = try makeModel(clock, zone: "America/New_York")
        let novemberFirst = GregorianDay(year: 2026, month: 11, day: 1).epochDay
        #expect(model.today == novemberFirst)
        clock.set(1_793_514_600_000)
        model.refreshDay()
        #expect(model.today == novemberFirst)
        clock.set(1_793_595_600_000)
        model.refreshDay()
        #expect(model.today == novemberFirst + 1)
    }

    @MainActor private func makeModel(_ clock: TestFrequencyClock, zone: String) throws -> StatisticsViewModel {
        let repository = GRDBAnalyticsRepository(database: try AppDatabase.inMemory())
        return try StatisticsViewModel(repository: repository, anomalies: repository,
            preferenceStore: TestFrequencyPreferences(), coverageStore: PrivateRecordingCoverageStore(),
            currency: CurrencyCode("CNY"), environment: LedgerEnvironment(now: { clock.read() }, zoneID: { zone }))
    }
}

private struct TestFrequencyPreferences: AnomalyPreferencesRepository {
    func load() async -> AnomalyPreferences { AnomalyPreferences() }
    func save(_ preferences: AnomalyPreferences) async {}
}

private final class TestFrequencyClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Int64

    init(_ instant: Int64) { self.instant = instant }
    func read() -> Int64 { lock.withLock { instant } }
    func set(_ next: Int64) { lock.withLock { instant = next } }
}
