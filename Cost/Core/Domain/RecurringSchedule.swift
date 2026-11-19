import Foundation

enum RecurringFrequency: String, CaseIterable, Sendable {
    case daily = "DAILY", weekdays = "WEEKDAYS", weeklySet = "WEEKLY_SET"
    case monthly = "MONTHLY", yearly = "YEARLY", interval = "INTERVAL"
}

enum RecurringIntervalUnit: String, CaseIterable, Sendable {
    case day = "DAY", week = "WEEK", month = "MONTH", year = "YEAR"
}

enum RecurringMonthPolicy: String, CaseIterable, Sendable {
    case lastDay = "LAST_DAY", skip = "SKIP"
}

enum RecurringCatchUp: String, CaseIterable, Sendable {
    case createMissed = "CREATE_MISSED", skipMissed = "SKIP_MISSED"
}

struct RecurringSchedule: Equatable, Sendable {
    // Civil days and wall time are independent of the device's current zone.
    static let days: ClosedRange<Int64> = -719_162...2_932_896 // 0001-01-01 through 9999-12-31
    private static let secondsPerDay: Int64 = 86_400
    var startDay: Int64
    var endDay: Int64?
    var minutes: Int
    var zoneID: String
    var frequency = RecurringFrequency.daily
    var intervalValue = 1
    var intervalUnit: RecurringIntervalUnit?
    var weekdaysMask = 0 // ISO Monday is bit zero.
    var dayOfMonth: Int?
    var monthOfYear: Int?
    var monthPolicy = RecurringMonthPolicy.lastDay

    func validate() throws {
        guard Self.days.contains(startDay), endDay.map({ (startDay...Self.days.upperBound).contains($0) }) ?? true,
              (0..<1440).contains(minutes), (0...127).contains(weekdaysMask),
              (1...Int(Int32.max)).contains(intervalValue),
              dayOfMonth.map({ (1...31).contains($0) }) ?? true,
              monthOfYear.map({ (1...12).contains($0) }) ?? true,
              frequency != .interval || intervalUnit != nil,
              frequency != .weeklySet || weekdaysMask != 0,
              ![.monthly, .yearly].contains(frequency) || dayOfMonth != nil,
              frequency != .yearly || monthOfYear != nil else { throw LedgerError.invalidField("recurringSchedule") }
        guard TimeZone(identifier: zoneID) != nil else { throw LedgerError.invalidTimeZone }
    }

    func localDay(at instant: Int64) throws -> Int64 {
        try OccurredAt(epochMillis: instant, zoneID: zoneID).localEpochDay
    }

    func next(after instant: Int64) throws -> Int64? {
        try occurrence(onOrAfter: localDay(at: instant) + 1)
    }

    func occurrence(onOrAfter target: Int64) throws -> Int64? {
        try validate()
        let lower = max(startDay, target)
        let upper = endDay ?? Self.days.upperBound
        guard lower <= upper else { return nil }
        let day: Int64?
        switch frequency {
        case .daily: day = lower
        case .weekdays, .weeklySet:
            let mask = frequency == .weekdays ? 31 : weekdaysMask
            day = (lower...min(lower + 6, upper)).first { candidate in
                let weekday = Int(((candidate + 3) % 7 + 7) % 7)
                return mask & (1 << weekday) != 0
            }
        case .monthly, .yearly, .interval:
            if frequency == .interval, let unit = intervalUnit, unit == .day || unit == .week {
                let step = Int64(intervalValue) * (unit == .week ? 7 : 1)
                day = startDay + Self.ceilDivide(lower - startDay, by: step) * step
            } else {
                day = monthOccurrence(lower: lower, upper: upper)
            }
        }
        guard let day, day <= upper, let zone = TimeZone(identifier: zoneID) else { return nil }
        return resolve(day: day, in: zone)
    }

    private func monthOccurrence(lower: Int64, upper: Int64) -> Int64? {
        let start = GregorianDay(epochDay: startDay)
        let target = GregorianDay(epochDay: lower)
        let end = GregorianDay(epochDay: upper).monthIndex
        let anchor: Int64
        let step: Int64
        let requested: Int64
        switch frequency {
        case .monthly:
            anchor = target.monthIndex; step = 1; requested = Int64(dayOfMonth ?? 1)
        case .yearly:
            anchor = target.year * 12 + Int64(monthOfYear ?? 1) - 1; step = 12; requested = Int64(dayOfMonth ?? 1)
        default:
            anchor = start.monthIndex; step = Int64(intervalValue) * (intervalUnit == .year ? 12 : 1)
            requested = start.day
        }
        var month = anchor + Self.ceilDivide(target.monthIndex - anchor, by: step) * step
        while month <= end {
            let start = GregorianDay(year: month / 12, month: month % 12 + 1, day: 1)
            let next = GregorianDay(year: (month + 1) / 12, month: (month + 1) % 12 + 1, day: 1)
            let length = next.epochDay - start.epochDay
            let day = start.epochDay + min(length, requested) - 1
            if day >= lower && (requested <= length || monthPolicy == .lastDay) { return day }
            month += step
        }
        return nil
    }

    private func resolve(day: Int64, in zone: TimeZone) -> Int64? {
        let wall = day * Self.secondsPerDay + Int64(minutes) * 60
        func offset(at seconds: Int64) -> Int64 {
            Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds))))
        }
        // The adjacent offsets also cover half-hour gaps and date-line jumps.
        let offsets = Set([-2, -1, 0, 1, 2].map { offset(at: wall + $0 * Self.secondsPerDay) })
        let candidates = offsets.map { wall - $0 }.map { utc in
            (utc: utc, displacement: utc + offset(at: utc) - wall)
        }
        return candidates.filter { $0.displacement >= 0 }.min {
            ($0.displacement, $0.utc) < ($1.displacement, $1.utc)
        }.map { $0.utc * 1000 }
    }

    private static func ceilDivide(_ value: Int64, by step: Int64) -> Int64 {
        value <= 0 ? 0 : 1 + (value - 1) / step
    }
}

// Proleptic Gregorian conversion based on 400-year eras, with March as the first month.
private struct GregorianDay {
    let year: Int64
    let month: Int64
    let day: Int64
    var monthIndex: Int64 { year * 12 + month - 1 }

    init(year: Int64, month: Int64, day: Int64) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(epochDay: Int64) {
        let shifted = epochDay + 719_468
        let era = shifted / 146_097
        let dayOfEra = shifted % 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let marchMonth = (5 * dayOfYear + 2) / 153
        month = marchMonth + (marchMonth < 10 ? 3 : -9)
        day = dayOfYear - (153 * marchMonth + 2) / 5 + 1
        year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    }

    var epochDay: Int64 {
        let marchYear = year - (month <= 2 ? 1 : 0)
        let era = marchYear / 400
        let yearOfEra = marchYear % 400
        let marchMonth = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * marchMonth + 2) / 5 + day - 1
        return era * 146_097 + yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear - 719_468
    }
}
