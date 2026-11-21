import Foundation
import Observation

enum StatisticsPreset: String, CaseIterable, Identifiable, Sendable {
    case week = "近 7 天", month = "近 30 天", quarter = "近 90 天", custom = "自定义"
    var id: Self { self }
    var days: Int64 {
        switch self {
        case .week: 7
        case .month, .custom: 30
        case .quarter: 90
        }
    }
}

@MainActor
@Observable
final class StatisticsViewModel {
    struct Query: Equatable, Sendable {
        let range: StatisticsRange
        let today: Int64
        let currency: CurrencyCode
        let retry: Int
    }

    struct DetectionQuery: Equatable, Sendable {
        let request: AnomalyRequest
        let retry: Int
    }

    struct FrequencyQuery: Equatable, Sendable {
        let today: Int64
        let window: AnomalyWindow
        let currency: CurrencyCode
        let retry: Int

        var range: SpendingFrequencyRange { SpendingFrequencyRange(today: today, window: window) }
    }

    private let repository: any StatisticsRepository
    private let anomalies: any AnomalyRepository
    private let preferenceStore: any AnomalyPreferencesRepository
    private let coverageStore: any RecordingCoverageRepository
    private let environment: LedgerEnvironment
    private let defaultCurrency: CurrencyCode
    private(set) var today: Int64?
    private(set) var currencies: [CurrencyCode]
    private(set) var preset = StatisticsPreset.month
    private(set) var customRange: StatisticsRange?
    private(set) var report: StatisticsReport?
    private(set) var reportFailed = false
    private(set) var detection: AnomalyResult?
    private(set) var detectionFailed = false
    private(set) var coverage: RecordingCoverage?
    private(set) var coverageLoadFailed = false
    private(set) var frequencyFailed = false
    private(set) var isSavingCoverage = false
    private var observedFrequency: (query: FrequencyQuery, days: Set<Int64>)?
    private(set) var preferences: AnomalyPreferences?
    private(set) var isSavingFeedback = false
    private(set) var isSavingPreferences = false
    var currency: CurrencyCode
    var anomalyWindow = AnomalyWindow.week
    var feedbackError: String?
    var coverageError: String?
    var statisticsRetry = 0
    var anomalyRetry = 0
    var frequencyRetry = 0

    init(repository: any StatisticsRepository, anomalies: any AnomalyRepository,
         preferenceStore: any AnomalyPreferencesRepository, coverageStore: any RecordingCoverageRepository,
         currency: CurrencyCode, environment: LedgerEnvironment) {
        self.repository = repository
        self.anomalies = anomalies
        self.preferenceStore = preferenceStore
        self.coverageStore = coverageStore
        self.environment = environment
        defaultCurrency = currency
        self.currency = currency
        currencies = [currency]
        refreshDay()
    }

    var query: Query? {
        guard let today, let range else { return nil }
        return Query(range: range, today: today, currency: currency, retry: statisticsRetry)
    }

    var range: StatisticsRange? {
        if preset == .custom { return customRange }
        guard let today else { return nil }
        return try? StatisticsRange(start: today - preset.days + 1, endInclusive: today)
    }

    var detectionQuery: DetectionQuery? {
        guard let today, let preferences, preferences.enabled else { return nil }
        return DetectionQuery(request: AnomalyRequest(today: today, window: anomalyWindow, currency: currency,
            sensitivity: preferences.sensitivity), retry: anomalyRetry)
    }

    var frequencyQuery: FrequencyQuery? {
        guard let today else { return nil }
        return FrequencyQuery(today: today, window: anomalyWindow, currency: currency, retry: frequencyRetry)
    }

    var frequency: SpendingFrequency? {
        guard let coverage, let observedFrequency, observedFrequency.query == frequencyQuery else { return nil }
        return SpendingFrequency(range: observedFrequency.query.range, coverage: coverage, expenseDays: observedFrequency.days)
    }

    func refreshDay() {
        let current = try? OccurredAt(epochMillis: environment.now(), zoneID: environment.zoneID()).localEpochDay
        guard today != current else { return }
        today = current
        detection = nil
        detectionFailed = false
        frequencyFailed = false
    }

    func select(_ preset: StatisticsPreset) {
        if preset != .custom { self.preset = preset }
    }

    func setRange(_ range: StatisticsRange) {
        customRange = range
        preset = .custom
    }

    func observeReport(_ query: Query?) async {
        guard self.query == query else { return }
        report = nil
        reportFailed = false
        guard let query else { return }
        do {
            for try await input in repository.observeStatistics(range: query.range, today: query.today, currency: query.currency) {
                let next = await Self.makeReport(query, input: input)
                guard !Task.isCancelled, self.query == query else { return }
                currencies = Set(input.currencies + [defaultCurrency]).sorted { $0.rawValue < $1.rawValue }
                report = next
            }
        } catch {
            if !Task.isCancelled, self.query == query { reportFailed = true }
        }
    }

    func loadPreferences() async {
        guard preferences == nil else { return }
        preferences = await preferenceStore.load()
    }

    func loadCoverage() async {
        guard coverage == nil else { return }
        coverageLoadFailed = false
        do {
            let stored = try await coverageStore.load()
            if coverage == nil { coverage = stored }
        } catch {
            if coverage == nil { coverageLoadFailed = true }
        }
    }

    func updateCoverage(_ action: RecordingCoverage.Action) async {
        refreshDay()
        guard !isSavingCoverage, var next = coverage, let today else { return }
        isSavingCoverage = true
        defer { isSavingCoverage = false }
        do {
            try next.apply(action, today: today)
            try await coverageStore.save(next)
            coverage = next
        } catch {
            coverageError = "无法保存记账覆盖，请重试。"
        }
    }

    func observeFrequency(_ query: FrequencyQuery?) async {
        guard frequencyQuery == query else { return }
        observedFrequency = nil
        frequencyFailed = false
        guard let query else { return }
        do {
            for try await days in anomalies.observeExpenseDays(in: query.range, currency: query.currency) {
                guard !Task.isCancelled, frequencyQuery == query else { return }
                observedFrequency = (query, days)
            }
        } catch {
            if !Task.isCancelled, frequencyQuery == query { frequencyFailed = true }
        }
    }

    func setPreferences(_ preferences: AnomalyPreferences) {
        guard !isSavingPreferences else { return }
        self.preferences = preferences
        isSavingPreferences = true
        Task {
            await preferenceStore.save(preferences)
            isSavingPreferences = false
        }
    }

    func observeAnomalies(_ query: DetectionQuery?) async {
        guard detectionQuery == query else { return }
        detection = nil
        detectionFailed = false
        guard let query else { return }
        do {
            for try await input in anomalies.observeAnomalyInput(query.request) {
                let next = await Self.detect(query.request, input: input)
                guard !Task.isCancelled, detectionQuery == query else { return }
                detection = next
            }
        } catch {
            if !Task.isCancelled, detectionQuery == query { detectionFailed = true }
        }
    }

    func saveFeedback(_ type: AnomalyFeedbackType, for finding: AnomalyFinding) async {
        guard !isSavingFeedback else { return }
        isSavingFeedback = true
        defer { isSavingFeedback = false }
        do { try await anomalies.saveAnomalyFeedback(finding.feedback(type, at: environment.now())) }
        catch { feedbackError = "无法保存异常反馈，请重试。" }
    }

    func clearFeedback() async {
        guard !isSavingFeedback else { return }
        isSavingFeedback = true
        defer { isSavingFeedback = false }
        do { try await anomalies.clearAnomalyFeedback() }
        catch { feedbackError = "无法清除异常反馈，请重试。" }
    }

    private nonisolated static func makeReport(_ query: Query, input: StatisticsInput) async -> StatisticsReport {
        StatisticsReport(range: query.range, today: query.today, currency: query.currency, input: input)
    }

    private nonisolated static func detect(_ request: AnomalyRequest, input: AnomalyInput) async -> AnomalyResult {
        DetectSpendingAnomalies.detect(request, input: input)
    }
}
