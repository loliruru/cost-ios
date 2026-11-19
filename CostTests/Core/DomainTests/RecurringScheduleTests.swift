import Foundation
import Testing
@testable import Cost

struct RecurringScheduleTests {
    @Test func androidDSTVectorsAndHalfHourTransition() throws {
        var rule = RecurringSchedule(startDay: day("2026-03-08"), minutes: 150, zoneID: "America/New_York")
        #expect(try rule.occurrence(onOrAfter: rule.startDay) == millis("2026-03-08T07:30:00Z"))
        rule.startDay = day("2026-11-01")
        rule.minutes = 90
        #expect(try rule.occurrence(onOrAfter: rule.startDay) == millis("2026-11-01T05:30:00Z"))
        rule = RecurringSchedule(startDay: day("2026-10-04"), minutes: 135, zoneID: "Australia/Lord_Howe")
        #expect(try rule.occurrence(onOrAfter: rule.startDay) == millis("2026-10-03T15:45:00Z"))
    }

    @Test func weekdaysAndInclusiveEnd() throws {
        var rule = RecurringSchedule(startDay: day("2026-09-04"), endDay: day("2026-09-08"), minutes: 480,
            zoneID: "UTC", frequency: .weekdays)
        #expect(try rule.occurrence(onOrAfter: day("2026-09-05")) == millis("2026-09-07T08:00:00Z"))
        rule.frequency = .weeklySet
        rule.weekdaysMask = (1 << 1) | (1 << 3)
        let finalOccurrence = try rule.occurrence(onOrAfter: rule.startDay)
        let last = try #require(finalOccurrence)
        #expect(last == millis("2026-09-08T08:00:00Z"))
        #expect(try rule.next(after: last) == nil)
        rule.weekdaysMask = 0
        #expect(throws: LedgerError.invalidField("recurringSchedule")) { try rule.validate() }
    }

    @Test func monthEndLeapYearsAndAnchoredIntervals() throws {
        var monthly = RecurringSchedule(startDay: day("2026-01-31"), minutes: 0, zoneID: "UTC", frequency: .monthly, dayOfMonth: 31)
        #expect(try monthly.occurrence(onOrAfter: day("2026-02-01")) == millis("2026-02-28T00:00:00Z"))
        monthly.monthPolicy = .skip
        #expect(try monthly.occurrence(onOrAfter: day("2026-02-01")) == millis("2026-03-31T00:00:00Z"))
        var yearly = RecurringSchedule(startDay: day("2024-02-29"), minutes: 0, zoneID: "UTC", frequency: .yearly,
            dayOfMonth: 29, monthOfYear: 2)
        #expect(try yearly.occurrence(onOrAfter: day("2025-01-01")) == millis("2025-02-28T00:00:00Z"))
        yearly.monthPolicy = .skip
        #expect(try yearly.occurrence(onOrAfter: day("2025-01-01")) == millis("2028-02-29T00:00:00Z"))

        var interval = RecurringSchedule(startDay: monthly.startDay, minutes: 0, zoneID: "UTC", frequency: .interval,
            intervalValue: 3, intervalUnit: .day)
        #expect(try interval.occurrence(onOrAfter: day("2026-02-10")) == millis("2026-02-12T00:00:00Z"))
        interval.intervalUnit = .week
        #expect(try interval.occurrence(onOrAfter: day("2026-02-10")) == millis("2026-02-21T00:00:00Z"))
        interval.intervalValue = 1
        interval.intervalUnit = .month
        interval.monthPolicy = .skip
        #expect(try interval.occurrence(onOrAfter: day("2026-02-01")) == millis("2026-03-31T00:00:00Z"))
        interval.startDay = yearly.startDay
        interval.intervalUnit = .year
        #expect(try interval.occurrence(onOrAfter: day("2024-03-01")) == millis("2028-02-29T00:00:00Z"))
        interval.intervalValue = Int(Int32.max)
        #expect(try interval.occurrence(onOrAfter: day("2024-03-01")) == nil)
    }

    private func day(_ text: String) -> Int64 { millis(text + "T00:00:00Z") / 86_400_000 }

    private func millis(_ text: String) -> Int64 {
        Int64(ISO8601DateFormatter().date(from: text)!.timeIntervalSince1970) * 1000
    }
}
