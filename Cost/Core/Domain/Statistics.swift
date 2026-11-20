import Foundation

struct StatisticsRange: Hashable, Sendable {
    static let maximumDays: Int64 = 3_660
    let days: Range<Int64>

    init(start: Int64, endInclusive: Int64) throws {
        guard RecurringSchedule.days.contains(start), RecurringSchedule.days.contains(endInclusive),
              start <= endInclusive, endInclusive - start < Self.maximumDays else {
            throw LedgerError.invalidField("statisticsRange")
        }
        days = start..<(endInclusive + 1)
    }

    var previous: Range<Int64> { (days.lowerBound - Int64(days.count))..<days.lowerBound }

    var lastYear: Range<Int64> {
        func shift(_ day: Int64) -> Int64 {
            let date = GregorianDay(epochDay: day)
            let year = date.year - 1
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            let adjustedDay = date.month == 2 && !leap ? min(date.day, 28) : date.day
            return GregorianDay(year: year, month: date.month, day: adjustedDay).epochDay
        }
        return shift(days.lowerBound)..<(shift(days.upperBound - 1) + 1)
    }
}

enum StatisticsPeriod: String, CaseIterable, Hashable, Identifiable, Sendable {
    case day = "日", month = "月", quarter = "季", year = "年"
    var id: Self { self }

    func bounds(containing day: Int64) -> Range<Int64> {
        if self == .day { return day..<(day + 1) }
        let date = GregorianDay(epochDay: day)
        let width: Int64
        switch self {
        case .day, .month: width = 1
        case .quarter: width = 3
        case .year: width = 12
        }
        let month = (date.month - 1) / width * width + 1
        let next = month - 1 + width
        let start = GregorianDay(year: date.year, month: month, day: 1).epochDay
        let end = GregorianDay(year: date.year + next / 12, month: next % 12 + 1, day: 1).epochDay
        return start..<end
    }
}

struct FrozenAmount: Sendable {
    let units: DecimalInteger
    let scale: Int

    func atScale(_ target: Int) -> DecimalInteger { units.timesPowerOfTen(target - scale) }
}

struct FrozenDayTotal: Sendable {
    let day: Int64
    let type: TransactionType
    let amount: FrozenAmount
}

struct FrozenCategoryTotal: Sendable {
    let id: String
    let name: String
    let amount: FrozenAmount
}

struct StatisticsInput: Sendable {
    let currencies: [CurrencyCode]
    let minimumScale: Int
    let current: [FrozenDayTotal]
    let previous: [FrozenDayTotal]
    let lastYear: [FrozenDayTotal]
    let today: [FrozenDayTotal]
    let categories: [FrozenCategoryTotal]
    let previousCategories: [FrozenCategoryTotal]
}

protocol StatisticsRepository: Sendable {
    func observeStatistics(range: StatisticsRange, today: Int64, currency: CurrencyCode)
        -> AsyncThrowingStream<StatisticsInput, Error>
}

struct StatisticsChange: Equatable, Sendable {
    let magnitude: DecimalInteger
    let decreases: Bool
    let basisPoints: DecimalInteger?
    var hasData: Bool { basisPoints != nil || !magnitude.isZero }

    init(current: DecimalInteger, baseline: DecimalInteger) {
        decreases = current < baseline
        magnitude = decreases ? baseline.subtracting(current) : current.subtracting(baseline)
        basisPoints = baseline.isZero ? nil : magnitude.timesPowerOfTen(4).dividedHalfEven(by: baseline)
    }
}

struct CashFlow: Equatable, Sendable {
    var income = DecimalInteger.zero
    var expense = DecimalInteger.zero

    mutating func add(_ result: Self) {
        income = income.adding(result.income)
        expense = expense.adding(result.expense)
    }
}

struct StatisticsBucket: Identifiable, Sendable {
    let days: Range<Int64>
    let cashFlow: CashFlow
    let partial: Bool
    var id: Int64 { days.lowerBound }
}

struct StatisticsAverage: Identifiable, Sendable {
    let period: StatisticsPeriod
    let units: DecimalInteger
    let count: Int
    let partial: Bool
    var id: StatisticsPeriod { period }
}

struct StatisticsCategory: Identifiable, Sendable {
    let id: String
    let name: String
    let amount: DecimalInteger
    let share: DecimalInteger
    let change: StatisticsChange
}

struct StatisticsReport: Sendable {
    let range: StatisticsRange
    let currency: CurrencyCode
    let scale: Int
    let total: CashFlow
    let series: [StatisticsPeriod: [StatisticsBucket]]
    let averages: [StatisticsAverage]
    let categories: [StatisticsCategory]
    let today: StatisticsChange
    let previous: StatisticsChange
    let lastYear: StatisticsChange

    init(range: StatisticsRange, today: Int64, currency: CurrencyCode, input: StatisticsInput) {
        self.range = range
        self.currency = currency
        let dailyScales = [input.current, input.previous, input.lastYear, input.today]
            .compactMap { $0.map(\.amount.scale).max() }
        let categoryScales = [input.categories, input.previousCategories].compactMap { $0.map(\.amount.scale).max() }
        let targetScale = (dailyScales + categoryScales + [input.minimumScale]).max() ?? 0
        scale = targetScale

        let daily = Self.dailyTotals(input.current, scale: targetScale)
        let sum = Self.sum(daily.values)
        total = sum
        let periods = StatisticsPeriod.allCases.map { period in
            let buckets = Self.buckets(period: period, range: range.days, daily: daily)
            return (period, buckets)
        }
        series = Dictionary(uniqueKeysWithValues: periods)
        averages = periods.map { period, buckets in
            StatisticsAverage(period: period, units: sum.expense.dividedHalfEven(by: DecimalInteger(String(buckets.count))),
                              count: buckets.count, partial: buckets.contains(where: \.partial))
        }
        let todayTotals = Self.dailyTotals(input.today, scale: targetScale)
        self.today = StatisticsChange(current: todayTotals[today]?.expense ?? .zero,
                                      baseline: todayTotals[today - 1]?.expense ?? .zero)
        previous = StatisticsChange(current: sum.expense, baseline: Self.sum(Self.dailyTotals(input.previous, scale: targetScale).values).expense)
        lastYear = StatisticsChange(current: sum.expense, baseline: Self.sum(Self.dailyTotals(input.lastYear, scale: targetScale).values).expense)

        let previousTotals = Self.categoryTotals(input.previousCategories, scale: targetScale)
        categories = Self.categoryTotals(input.categories, scale: targetScale).map { id, value in
            StatisticsCategory(id: id, name: value.name, amount: value.amount,
                share: sum.expense.isZero ? .zero : value.amount.timesPowerOfTen(4).dividedHalfEven(by: sum.expense),
                change: StatisticsChange(current: value.amount, baseline: previousTotals[id]?.amount ?? .zero))
        }.sorted {
            if $0.amount != $1.amount { return $0.amount > $1.amount }
            return $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
    }

    private static func dailyTotals(_ rows: [FrozenDayTotal], scale: Int) -> [Int64: CashFlow] {
        var days: [Int64: CashFlow] = [:]
        for row in rows {
            let amount = row.amount.atScale(scale)
            switch row.type {
            case .income: days[row.day, default: CashFlow()].income = (days[row.day]?.income ?? .zero).adding(amount)
            case .expense: days[row.day, default: CashFlow()].expense = (days[row.day]?.expense ?? .zero).adding(amount)
            }
        }
        return days
    }

    private static func sum(_ values: some Sequence<CashFlow>) -> CashFlow {
        values.reduce(into: CashFlow()) { $0.add($1) }
    }

    private static func categoryTotals(_ rows: [FrozenCategoryTotal], scale: Int)
        -> [String: (name: String, amount: DecimalInteger)] {
        var categories: [String: (name: String, amount: DecimalInteger)] = [:]
        for row in rows {
            categories[row.id] = (row.name, (categories[row.id]?.amount ?? .zero).adding(row.amount.atScale(scale)))
        }
        return categories
    }

    private static func buckets(period: StatisticsPeriod, range: Range<Int64>, daily: [Int64: CashFlow]) -> [StatisticsBucket] {
        var buckets: [StatisticsBucket] = []
        var day = range.lowerBound
        while day < range.upperBound {
            let bounds = period.bounds(containing: day)
            let visible = day..<min(range.upperBound, bounds.upperBound)
            let amount = sum(visible.lazy.compactMap { daily[$0] })
            buckets.append(StatisticsBucket(days: visible, cashFlow: amount, partial: visible != bounds))
            day = visible.upperBound
        }
        return buckets
    }
}
