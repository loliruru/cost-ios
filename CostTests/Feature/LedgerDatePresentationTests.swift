import Foundation
import Testing
@testable import Cost

struct LedgerDatePresentationTests {
    @Test func detailUsesFrozenZoneRatherThanCurrentDeviceZone() throws {
        let instant = try #require(Calendar.utc.date(from: DateComponents(year: 2026, month: 1, day: 15)))
        let millis = Int64(instant.timeIntervalSince1970 * 1000)
        #expect(try LedgerStyle.occurred(OccurredAt(epochMillis: millis, zoneID: "Asia/Singapore")) == "2026-01-15 08:00")
        #expect(try LedgerStyle.occurred(OccurredAt(epochMillis: millis, zoneID: "America/Los_Angeles")) == "2026-01-14 16:00")
    }
    @Test func filterUsesGregorianHalfOpenDaysAcrossLeapDay() throws {
        let start = try #require(DateComponents(year: 2024, month: 2, day: 28).dateEpochDay)
        let inclusiveEnd = try #require(DateComponents(year: 2024, month: 3, day: 1).dateEpochDay)
        #expect(inclusiveEnd + 1 - start == 3)
        #expect(Calendar.localGregorian.identifier == .gregorian)
    }
}
