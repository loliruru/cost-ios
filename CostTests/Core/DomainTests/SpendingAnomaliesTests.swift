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

    @Test func positiveDailySamplesRetainTheirSpreadAndIgnoreCalendarGaps() throws {
        let history = historical(["1000", "1000", "4000", "8000", "9000"], across: [68, 71, 74, 79, 89])
        let rows = history + [sample("usual", day: 99, units: "15000"), sample("high", day: 100, units: "24800")]
        let result = detect(try request(), rows: rows)
        #expect(result.findings.count == 3)
        #expect(result.findings.allSatisfy { $0.day == 100 && $0.thresholdIsApproximate })
        #expect(result.sampleCounts[.day] == 5...5)
        #expect(result.sampleCounts[.category] == 5...5)
    }

    @Test func singleHistoricalExtremeDoesNotRaiseTheMeanFloor() throws {
        let inputs = ["100000", "500000"]
        for extreme in inputs {
            let rows = historical(["3900", "4000", "4000", "4100", extreme])
                + [sample("equal", day: 98, units: "10000"), sample("above", day: 99, units: "10001")]
            let result = detect(try request(), rows: rows)
            #expect(result.findings.count == 3)
            #expect(result.findings.allSatisfy {
                $0.day == 99 && $0.threshold.units == DecimalInteger("100").timesPowerOfTen(20)
                    && !$0.thresholdIsApproximate
            })
        }
    }

    @Test func fractionalIQRThresholdUsesStrictIntegerComparison() throws {
        let history = historical(["4000", "4000", "4000", "7000", "8000"])
        let rows = history + [sample("below", day: 98, units: "12895"), sample("above", day: 99, units: "12896")]
        let result = detect(try request(), rows: rows)
        #expect(result.findings.count == 3)
        #expect(result.findings.allSatisfy { $0.day == 99 && $0.thresholdIsApproximate })
    }

    @Test func lowAmountKeepsSensitivityAndMinorUnitBoundary() throws {
        let mixedScales = [
            sample("historic-finer-scale", day: 74, units: "1000", scale: 3)
        ] + historical(["100", "100", "100", "500"])
        let rows = mixedScales + [
            sample("equal", day: 98, units: "250"),
            sample("cent-above", day: 99, units: "251"),
            sample("five", day: 100, units: "500")
        ]
        let standard = detect(try request(), rows: rows)
        #expect(Set(standard.findings.map(\.day)) == [99, 100])
        let high = detect(try request(sensitivity: .high), rows: rows)
        #expect(Set(high.findings.map(\.day)) == [98, 99, 100])
        let low = detect(try request(sensitivity: .low), rows: rows)
        #expect(Set(low.findings.map(\.day)) == [100])
    }

    @Test func missingAndZeroAmountsDoNotMeetTheMinimum() throws {
        let candidate = sample("candidate", day: 100, units: "500")
        let fixed = try request()
        for history in [[], historical(Array(repeating: "0", count: 5)), historical(["100", "100", "100", "100", "0"])] {
            let result = detect(fixed, rows: history + [candidate])
            #expect(result.status == .insufficientData)
            #expect(result.findings.isEmpty)
        }
    }

    @Test func samplesAreCountedPerKindAndPerCategory() throws {
        let base = (0..<9).map { sample("food-\($0)", day: 82, units: "100") }
        let coffee = (0..<4).map { sample("coffee-\($0)", day: 81 + Int64($0), units: "100", category: "coffee") }
        let rows = base + coffee + [
            sample("food", day: 100, units: "500"),
            sample("coffee", day: 100, units: "500", category: "coffee")
        ]
        let fixed = try request()
        let few = detect(fixed, rows: rows)
        #expect(few.sampleCounts[.transaction] == 9...9)
        #expect(few.sampleCounts[.day] == nil)
        #expect(few.sampleCounts[.category] == nil)
        #expect(few.findings.compactMap(\.transactionID) == ["food"])
        let ten = detect(fixed, rows: rows + [sample("food-10", day: 82, units: "100")])
        #expect(ten.sampleCounts[.transaction] == 10...10)
    }

    @Test func midnightFinalizesDailyFindingsWithoutChangingTheirIDs() throws {
        let rows = historical(Array(repeating: "100", count: 5)) + [sample("today", day: 100, units: "500")]
        let before = detect(try request(), rows: rows)
        #expect(Set(before.findings.filter(\.isProvisional).map(\.kind)) == [.day, .category])
        let after = detect(try request(today: 101), rows: rows)
        #expect(after.findings.allSatisfy { !$0.isProvisional })
        #expect(before.findings.map(\.id) == after.findings.map(\.id))
    }

    private func request(today: Int64 = 100, sensitivity: AnomalySensitivity = .normal) throws -> AnomalyRequest {
        AnomalyRequest(today: today, window: .week, currency: try CurrencyCode("CNY"), sensitivity: sensitivity)
    }

    private func detect(_ request: AnomalyRequest, rows: [AnomalyTransaction]) -> AnomalyResult {
        DetectSpendingAnomalies.detect(request, input: AnomalyInput(transactions: rows, daily: rows.map(daily), feedback: []))
    }

    private func historical(_ units: [String], across days: [Int64]? = nil) -> [AnomalyTransaction] {
        units.enumerated().map { index, value in
            sample("historic-\(index)", day: days?[index] ?? (75 + Int64(index)), units: value)
        }
    }

    private func sample(_ id: String, day: Int64, units: String, category: String = "food", scale: Int = 2) -> AnomalyTransaction {
        AnomalyTransaction(id: id, day: day, categoryID: category, categoryName: "餐饮",
                           amount: FrozenAmount(units: DecimalInteger(units), scale: scale))
    }

    private func daily(_ sample: AnomalyTransaction) -> AnomalyDay {
        AnomalyDay(day: sample.day, categoryID: sample.categoryID, amount: sample.amount)
    }
}
