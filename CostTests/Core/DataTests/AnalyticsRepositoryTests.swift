import Foundation
import GRDB
import Testing
@testable import Cost

struct AnalyticsRepositoryTests {
    @Test func frozenTotalsExceedInt64AndKeepScalesCurrenciesAndCalendarDays() async throws {
        let database = try AppDatabase.inMemory()
        let ledger = GRDBLedgerRepository(database: database)
        let repository = GRDBAnalyticsRepository(database: database)
        let cny = try CurrencyCode("CNY")
        let usd = try CurrencyCode("USD")
        let range = try StatisticsRange(start: 19_781, endInclusive: 19_783)
        let entries: [LedgerTransaction] = [
            try entry("large-1", day: 19_781, units: .max, code: cny),
            try entry("large-2", day: 19_781, units: .max, code: cny),
            try entry("sub-cent", day: 19_781, units: 1, code: cny, scale: 3),
            try entry("income", day: 19_783, units: 100, code: cny, type: .income),
            try entry("usd", day: 19_781, units: 921, code: usd),
            try entry("previous", day: 19_780, units: 100, code: cny),
            try entry("prior-year", day: 19_416, units: 300, code: cny),
            try entry("future", day: 19_784, units: 1, code: cny),
            try TestLedger.transaction(id: "foreign", units: 100, code: "USD", rate: "7", baseUnits: 700,
                method: .latest, occurred: 19_781 * 86_400_000)
        ]
        try await ledger.write { db in
            for entry in entries { try GRDBLedgerRepository.insertTransaction(db, entry) }
        }
        let deleted = try await ledger.softDeleteTransaction(id: "future", at: 11)
        #expect(deleted)
        let deletedCurrent = try entry("deleted", day: 19_782, units: 999, code: cny, deleted: 11)
        _ = try await ledger.createTransaction(deletedCurrent)
        var stream = repository.observeStatistics(range: range, today: 19_783, currency: cny).makeAsyncIterator()
        let first = try await stream.next()
        let input = try #require(first)
        let report = StatisticsReport(range: range, today: 19_783, currency: cny, input: input)
        #expect(input.currencies == [cny, usd])
        #expect(report.scale == 3)
        #expect(report.total.expense.description == "184467440737095523141")
        #expect(report.total.income.description == "1000")
        #expect(report.categories.first?.amount == report.total.expense)
        #expect(report.series[.day]?[1].cashFlow == CashFlow())
        #expect(report.series[.month]?.count == 2)
        #expect(report.averages.first { $0.period == .month }?.partial == true)
        #expect(report.today.hasData == false)
        #expect(range.lastYear == 19_416..<19_418)
        #expect(report.lastYear.magnitude == report.total.expense.subtracting(DecimalInteger("3000")))
        #expect(report.previous.magnitude == report.total.expense.subtracting(DecimalInteger("1000")))

        let updatedRate = try FiatQuote(id: "updated-rate", original: usd, base: cny, rate: DecimalRate("8"),
            providerID: "FIXTURE", dataTimestamp: 1000, rateEpochDay: nil, fetchedAt: 1001, expiresAt: 3000, kind: .latest)
        try await ledger.saveFiatQuote(updatedRate)
        var reloaded = repository.observeStatistics(range: range, today: 19_783, currency: cny).makeAsyncIterator()
        let refreshed = try await reloaded.next()
        let unchanged = StatisticsReport(range: range, today: 19_783, currency: cny, input: try #require(refreshed))
        #expect(unchanged.total == report.total)
    }

    @Test func anomalyIgnoresRecurringAndSoftDeletedRowsAndPersistsFeedbackAcrossReopen() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("analytics.sqlite")
        let database = try await AppDatabase.open(at: url)
        let ledger = GRDBLedgerRepository(database: database)
        let repository = GRDBAnalyticsRepository(database: database)
        let code = try CurrencyCode("CNY")
        let request = AnomalyRequest(today: 40, window: .week, currency: code, sensitivity: .normal)
        let samples = try (0..<5).map { index in
            try entry("history-\(index)", day: 20 + Int64(index), units: 100, code: code)
        }
        let candidate = try entry("candidate", day: 40, units: 500, code: code)
        let recurring = try entry("recurring", day: 40, units: .max, code: code, source: .recurring)
        let deleted = try entry("deleted", day: 40, units: .max, code: code, deleted: 11)
        try await ledger.write { db in
            for entry in samples + [candidate, recurring, deleted] { try GRDBLedgerRepository.insertTransaction(db, entry) }
        }

        let detected = try await detect(repository, request)
        #expect(detected.status == .ready)
        #expect(detected.totalFindings == 3)
        let single = try #require(detected.findings.first { $0.kind == .transaction })
        #expect(single.transactionID == "candidate")
        #expect(detected.findings.allSatisfy { $0.amount.units == DecimalInteger("5000000000000000000") })
        try await repository.saveAnomalyFeedback(single.feedback(.markedNormal, at: 12))
        let reopened = GRDBAnalyticsRepository(database: try await AppDatabase.open(at: url))
        let afterReopen = try await detect(reopened, request)
        #expect(afterReopen.totalFindings == 2)
        try await reopened.clearAnomalyFeedback()
        let afterClear = try await detect(reopened, request)
        #expect(afterClear.totalFindings == 3)
    }

    @Test func anomalyMakesNoDecisionWhenSentinelRowIsPresent() async throws {
        let database = try AppDatabase.inMemory()
        let ledger = GRDBLedgerRepository(database: database)
        let code = try CurrencyCode("CNY")
        try await ledger.write { db in
            for index in 0...DetectSpendingAnomalies.sampleLimit {
                try GRDBLedgerRepository.insertTransaction(db, entry("sample-\(index)", day: 40, units: 100, code: code))
            }
        }
        let request = AnomalyRequest(today: 40, window: .month, currency: code, sensitivity: .normal)
        let result = try await detect(GRDBAnalyticsRepository(database: database), request)
        #expect(result.status == .sampleLimit)
        #expect(result.totalFindings == 0)
    }

    private func detect(_ repository: GRDBAnalyticsRepository, _ request: AnomalyRequest) async throws -> AnomalyResult {
        var stream = repository.observeAnomalyInput(request).makeAsyncIterator()
        let input = try await stream.next()
        return DetectSpendingAnomalies.detect(request, input: try #require(input))
    }

    private func entry(_ id: String, day: Int64, units: Int64, code: CurrencyCode, scale: Int = 2,
                       type: TransactionType = .expense, source: TransactionSource = .manual,
                       deleted: Int64? = nil) throws -> LedgerTransaction {
        let amount = try Money(minorUnits: units, currencyCode: code, scale: scale)
        return try LedgerTransaction(id: id, type: type, original: amount, convertedBase: amount, exchangeRate: .identity(),
            categoryID: type == .expense ? "seed-expense-other" : "seed-income-other", accountID: "seed-default-account",
            occurredAt: OccurredAt(epochMillis: day * 86_400_000, zoneID: "UTC"),
            note: nil, source: source, sourceID: source == .recurring ? "fixture-rule" : nil, requestKey: nil, createdAt: 10,
            updatedAt: deleted ?? 10, deletedAt: deleted, tagIDs: [])
    }
}
