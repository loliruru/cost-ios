struct RecordingCoverage: Codable, Equatable, Sendable {
    enum Action: Sendable {
        case start(Int64), pause, resume, confirmDay(Int64), markUnknown(Int64)
    }

    private(set) var hasStarted = false
    private(set) var activeStart: Int64?
    private var completed: [Range<Int64>] = []
    private var confirmedDays: Set<Int64> = []
    private var unknownDays: Set<Int64> = []

    var hasCoverageDeclaration: Bool { hasStarted || !confirmedDays.isEmpty }

    func contains(_ day: Int64) -> Bool {
        guard !unknownDays.contains(day) else { return false }
        if confirmedDays.contains(day) || activeStart.map({ day >= $0 }) == true { return true }
        return completed.contains { $0.contains(day) }
    }

    mutating func apply(_ action: Action, today: Int64) throws {
        switch action {
        case .start(let day):
            guard !hasStarted, day <= today + 1, RecurringSchedule.days.contains(day) else {
                throw LedgerError.invalidField("coverageStart")
            }
            hasStarted = true
            activeStart = day
        case .pause:
            guard let start = activeStart else { return }
            if start < today { completed.append(start..<today) }
            activeStart = nil
        case .resume:
            guard hasStarted, activeStart == nil, RecurringSchedule.days.contains(today + 1) else { return }
            activeStart = today + 1
        case .confirmDay(let day):
            try Self.requireCompletedDay(day, today: today)
            unknownDays.remove(day)
            confirmedDays.insert(day)
        case .markUnknown(let day):
            try Self.requireCompletedDay(day, today: today)
            confirmedDays.remove(day)
            unknownDays.insert(day)
        }
    }

    private static func requireCompletedDay(_ day: Int64, today: Int64) throws {
        guard day < today, RecurringSchedule.days.contains(day) else { throw LedgerError.invalidField("coverageDay") }
    }
}

protocol RecordingCoverageRepository: Sendable {
    func load() async throws -> RecordingCoverage
    func save(_ coverage: RecordingCoverage) async throws
}

struct SpendingFrequencyRange: Sendable {
    let recent: Range<Int64>
    let history: Range<Int64>

    init(today: Int64, window: AnomalyWindow) {
        let start = today - window.rawValue
        recent = start..<today
        history = (start - 90)..<start
    }

    var sampleRange: Range<Int64> { history.lowerBound..<recent.upperBound }
}

struct SpendingFrequency: Equatable, Sendable {
    struct Period: Equatable, Sendable {
        let days: Range<Int64>
        let coveredDays: Int
        let spendingDays: Int

        var basisPoints: DecimalInteger? {
            guard coveredDays > 0 else { return nil }
            return DecimalInteger(String(spendingDays)).timesPowerOfTen(4)
                .dividedHalfEven(by: DecimalInteger(String(coveredDays)))
        }
    }

    enum CoverageIssue: Equatable, Sendable {
        case unconfirmed, tooFewRecent(required: Int), tooFewHistorical, missingWeekdays
    }

    let recent: Period
    let history: Period
    let issues: [CoverageIssue]

    init(range: SpendingFrequencyRange, coverage: RecordingCoverage, expenseDays: Set<Int64>) {
        let recentDays = range.recent.filter { coverage.contains($0) }
        let recentWeekdays = Set(recentDays.map(Self.weekday))
        let shortRange = (range.history.upperBound - 30)..<range.history.upperBound
        let shortDays = shortRange.filter { coverage.contains($0) }
        let firstChoice = shortDays.count >= 28 && Self.hasWeekdayCoverage(recentWeekdays, in: shortDays)
        let historyRange = firstChoice ? shortRange : range.history
        let historicalDays = firstChoice ? shortDays : historyRange.filter { coverage.contains($0) }
        recent = Period(days: range.recent, coveredDays: recentDays.count,
                        spendingDays: recentDays.filter { expenseDays.contains($0) }.count)
        history = Period(days: historyRange, coveredDays: historicalDays.count,
                         spendingDays: historicalDays.filter { expenseDays.contains($0) }.count)

        guard coverage.hasCoverageDeclaration else {
            issues = [.unconfirmed]
            return
        }
        let minimum = range.recent.count == 7 ? 5 : 21
        var issues: [CoverageIssue] = []
        if recentDays.count < minimum { issues.append(.tooFewRecent(required: minimum)) }
        if historicalDays.count < 28 { issues.append(.tooFewHistorical) }
        else if !Self.hasWeekdayCoverage(recentWeekdays, in: historicalDays) { issues.append(.missingWeekdays) }
        self.issues = issues
    }

    private static func weekday(_ day: Int64) -> Int64 { (day % 7 + 7) % 7 }

    private static func hasWeekdayCoverage(_ weekdays: Set<Int64>, in days: [Int64]) -> Bool {
        let counts = Dictionary(grouping: days, by: weekday)
        return weekdays.allSatisfy { (counts[$0]?.count ?? 0) >= 3 }
    }
}
