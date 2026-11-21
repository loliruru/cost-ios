import Testing
@testable import Cost

struct SpendingAnomaliesTests {
    @Test func fiveRecentSpendingDaysBecomeBaselineOnlyAfterLeavingTheDetectionWindow() throws {
        let code = try CurrencyCode("CNY")
        let history = (96...100).map { sample("recent-\($0)", day: Int64($0), units: "100") }
        let rows = history + [sample("spike", day: 106, units: "1000")]
        let input = AnomalyInput(transactions: rows, daily: rows.map(daily), feedback: [])

        let recent = AnomalyRequest(today: 100, window: .week, currency: code, sensitivity: .normal)
        #expect(DetectSpendingAnomalies.detect(recent, input: input).status == .insufficientData)

        let fourHistoricalDays = AnomalyRequest(today: 106, window: .week, currency: code, sensitivity: .normal)
        #expect(DetectSpendingAnomalies.detect(fourHistoricalDays, input: input).status == .insufficientData)

        let fiveHistoricalDays = AnomalyRequest(today: 107, window: .week, currency: code, sensitivity: .normal)
        let result = DetectSpendingAnomalies.detect(fiveHistoricalDays, input: input)
        #expect(result.status == .ready)
        #expect(result.findings.contains { $0.transactionID == "spike" && $0.activeSamples == 5 })
    }

    @Test func exactThresholdUsesActiveMedianAndChoosesNinetyDaysOnlyWhenNeeded() throws {
        let code = try CurrencyCode("CNY")
        let request = AnomalyRequest(today: 100, window: .week, currency: code, sensitivity: .normal)
        let history = [10, 40, 50, 60, 80].map { sample("row-\($0)", day: Int64($0), units: "100") }
        let boundary = sample("at-threshold", day: 98, units: "250")
        let high = sample("over-threshold", day: 99, units: "251")
        let input = AnomalyInput(transactions: history + [boundary, high],
                                 daily: (history + [boundary, high]).map(daily), feedback: [])
        let result = DetectSpendingAnomalies.detect(request, input: input)
        #expect(result.status == .ready)
        #expect(result.totalFindings == 3)
        #expect(result.findings.allSatisfy { $0.day == 99 && $0.baselineDays == 90 && $0.activeSamples == 5 })
        let incomplete = DetectSpendingAnomalies.detect(request, input: AnomalyInput(transactions: [high], daily: [daily(high)], feedback: []))
        #expect(incomplete.status == .insufficientData)
        #expect(incomplete.insufficientGroups == 3)
    }

    @Test func markedNormalIncludesBothTwentyPercentEdgesAndIgnoresFeedbackFromOtherVersions() throws {
        let code = try CurrencyCode("CNY")
        let request = AnomalyRequest(today: 100, window: .week, currency: code, sensitivity: .normal)
        let history = (75..<80).map { sample("history-\($0)", day: Int64($0), units: "100") }
        let rows = history + [
            sample("lower-edge", day: 100, units: "400"), sample("upper-edge", day: 100, units: "600"),
            sample("lower-outside", day: 100, units: "399"), sample("upper-outside", day: 100, units: "601")
        ]
        let marked = AnomalyFeedback(id: "fixture", type: .markedNormal, kind: .transaction, categoryID: "food",
            currency: code, amount: FrozenAmount(units: DecimalInteger("5000"), scale: 3), version: 1, createdAt: 0)
        let old = AnomalyFeedback(id: "prior-version", type: .markedNormal, kind: .transaction, categoryID: "food",
            currency: code, amount: FrozenAmount(units: DecimalInteger("600"), scale: 2), version: 0, createdAt: 0)
        let result = DetectSpendingAnomalies.detect(request, input: AnomalyInput(transactions: rows, daily: [], feedback: [marked, old]))
        #expect(Set(result.findings.compactMap(\.transactionID)) == ["lower-outside", "upper-outside"])
        #expect(result.findings.allSatisfy { $0.baselineDays == 30 })
        let ignored = try #require(result.findings.first { $0.transactionID == "upper-outside" }).feedback(.ignoredOnce, at: 1)
        let next = DetectSpendingAnomalies.detect(request, input: AnomalyInput(transactions: rows, daily: [], feedback: [marked, ignored]))
        #expect(next.findings.compactMap(\.transactionID) == ["lower-outside"])
    }

    private func sample(_ id: String, day: Int64, units: String) -> AnomalyTransaction {
        AnomalyTransaction(id: id, day: day, categoryID: "food", categoryName: "餐饮",
                           amount: FrozenAmount(units: DecimalInteger(units), scale: 2))
    }

    private func daily(_ sample: AnomalyTransaction) -> AnomalyDay {
        AnomalyDay(day: sample.day, categoryID: sample.categoryID, amount: sample.amount)
    }
}
