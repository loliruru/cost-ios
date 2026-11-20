import Testing
@testable import Cost

struct StatisticsTests {
    @Test func zeroDaysCountTowardAveragesAndZeroBaselineHasNoPercentage() throws {
        let code = try CurrencyCode("CNY")
        let range = try StatisticsRange(start: 19_781, endInclusive: 19_782)
        let amount = FrozenAmount(units: DecimalInteger("5"), scale: 2)
        let input = StatisticsInput(currencies: [code], minimumScale: 2,
            current: [FrozenDayTotal(day: 19_781, type: .expense, amount: amount)],
            previous: [], lastYear: [], today: [], categories: [], previousCategories: [])
        let report = StatisticsReport(range: range, today: 19_782, currency: code, input: input)
        #expect(report.series[.day]?.count == 2)
        #expect(report.averages.first?.units == DecimalInteger("2"))
        #expect(report.averages.first?.partial == false)
        #expect(report.previous.magnitude == DecimalInteger("5"))
        #expect(report.previous.basisPoints == nil)
        #expect(report.lastYear.hasData)
        #expect(range.previous == 19_779..<19_781)
        #expect(range.lastYear == 19_416..<19_417)
        #expect(throws: LedgerError.invalidField("statisticsRange")) {
            try StatisticsRange(start: 0, endInclusive: StatisticsRange.maximumDays)
        }
    }

    @Test func calendarBucketsUseActualPeriodBoundaries() throws {
        let start = GregorianDay(year: 2024, month: 1, day: 1).epochDay
        let end = GregorianDay(year: 2025, month: 1, day: 1).epochDay
        let range = try StatisticsRange(start: start, endInclusive: end - 1)
        let code = try CurrencyCode("CNY")
        let report = StatisticsReport(range: range, today: end - 1, currency: code,
            input: StatisticsInput(currencies: [code], minimumScale: 2, current: [], previous: [], lastYear: [],
                today: [], categories: [], previousCategories: []))
        #expect(report.averages.map(\.count) == [366, 12, 4, 1])
        #expect(report.averages.allSatisfy { !$0.partial })
        #expect(report.series[.quarter]?.first?.days.count == 91)
    }
}
