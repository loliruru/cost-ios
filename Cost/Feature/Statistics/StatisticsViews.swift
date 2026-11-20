import Charts
import SwiftUI

struct StatisticsView: View {
    @Bindable var model: StatisticsViewModel
    @State private var period = StatisticsPeriod.day
    @State private var pickingDates = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Menu {
                        ForEach(StatisticsPreset.allCases) { preset in
                            Button(preset.rawValue) {
                                if preset == .custom { pickingDates = true }
                                else { model.select(preset); period = .day }
                            }
                        }
                    } label: {
                        Label(model.preset.rawValue, systemImage: "calendar")
                    }.accessibilityIdentifier("statistics.range")
                    if let range = model.range { Text(StatisticsDisplay.range(range.days)).foregroundStyle(.secondary) }
                    Picker("冻结本位币", selection: $model.currency) {
                        ForEach(model.currencies, id: \.self) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("statistics.currency")
                }
                if model.reportFailed {
                    ContentUnavailableView("无法读取统计", systemImage: "chart.bar.xaxis")
                    Button("重试") { model.statisticsRetry += 1 }
                } else if let report = model.report, model.range == report.range, model.currency == report.currency {
                    summary(report)
                    if !report.total.expense.isZero || !report.total.income.isZero {
                        trend(report)
                        if !report.categories.isEmpty { categories(report) }
                    } else {
                        Text("所选期间没有账单").accessibilityIdentifier("statistics.empty")
                    }
                    comparisons(report)
                    averages(report)
                } else {
                    ProgressView("读取统计")
                }
            }
            .navigationTitle("统计")
            .toolbar {
                NavigationLink {
                    SpendingAnomaliesView(model: model)
                } label: {
                    Label("异常开支", systemImage: "exclamationmark.circle")
                }.accessibilityIdentifier("statistics.anomalies.open")
            }
            .task(id: model.query) { await model.observeReport(model.query) }
            .sheet(isPresented: $pickingDates) {
                if let initial = model.range, let today = model.today {
                    StatisticsDateSheet(initial: initial, today: today) { range in
                        period = range.days.count <= 90 ? .day : .month
                        model.setRange(range)
                    }
                }
            }
        }
    }

    private func summary(_ report: StatisticsReport) -> some View {
        let total = report.total
        let negative = total.income < total.expense
        let net = negative ? total.expense.subtracting(total.income) : total.income.subtracting(total.expense)
        return Section("收支概览") {
            summaryAmount("收入", StatisticsDisplay.money(total.income, in: report), id: "statistics.total.income")
            summaryAmount("支出", StatisticsDisplay.money(total.expense, in: report), id: "statistics.total.expense")
            summaryAmount("净额", (negative ? "−" : "") + StatisticsDisplay.money(net, in: report), id: "statistics.total.net")
        }
    }

    private func summaryAmount(_ label: String, _ value: String, id: String) -> some View {
        LabeledContent(label, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value))
            .accessibilityIdentifier(id)
    }

    private func trend(_ report: StatisticsReport) -> some View {
        let buckets = report.series[period] ?? []
        let visible = Array(buckets.suffix(120))
        let peak = visible.reduce(DecimalInteger.zero) { max($0, max($1.cashFlow.income, $1.cashFlow.expense)) }
        return Section("收支趋势") {
            Picker("周期", selection: $period) {
                ForEach(StatisticsPeriod.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)

            Chart(visible) { bucket in
                let day = Int(bucket.id)
                let income = StatisticsDisplay.chartUnits(bucket.cashFlow.income, relativeTo: peak)
                let expense = StatisticsDisplay.chartUnits(bucket.cashFlow.expense, relativeTo: peak)
                if visible.count == 1 {
                    PointMark(x: .value("期间", day), y: .value("金额", income))
                        .foregroundStyle(by: .value("收支", "收入"))
                    PointMark(x: .value("期间", day), y: .value("金额", expense))
                        .foregroundStyle(by: .value("收支", "支出"))
                } else {
                    LineMark(x: .value("期间", day), y: .value("金额", income), series: .value("收支", "收入"))
                        .foregroundStyle(by: .value("收支", "收入"))
                    LineMark(x: .value("期间", day), y: .value("金额", expense), series: .value("收支", "支出"))
                        .foregroundStyle(by: .value("收支", "支出"))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...1_000_000)
            .frame(height: 180)
            .accessibilityHidden(true)
            if let first = visible.first, let last = visible.last {
                Text(StatisticsDisplay.range(first.days.lowerBound..<last.days.upperBound))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            NavigationLink {
                List(buckets) { bucket in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(StatisticsDisplay.range(bucket.days) + (bucket.partial ? "（未满期）" : "")).font(.headline)
                        LabeledContent("收入", value: StatisticsDisplay.money(bucket.cashFlow.income, in: report))
                        LabeledContent("支出", value: StatisticsDisplay.money(bucket.cashFlow.expense, in: report))
                    }
                }.navigationTitle("趋势明细")
            } label: {
                Label("趋势明细（\(buckets.count) 个周期）", systemImage: "list.bullet")
            }.accessibilityIdentifier("statistics.trend.detail")
        }
    }

    private func categories(_ report: StatisticsReport) -> some View {
        let entries = report.categories
        let colors: [Color] = [.indigo, .teal, .orange, .purple, .blue, .pink, .green, .gray]
        let slices = Array(entries.prefix(7).map(\.amount)) + (
            entries.count > 7 ? [entries.dropFirst(7).reduce(DecimalInteger.zero) { $0.adding($1.amount) }] : [])
        return Section("支出构成") {
            Chart(Array(slices.indices), id: \.self) { index in
                SectorMark(angle: .value("支出", max(1, StatisticsDisplay.chartUnits(slices[index], relativeTo: report.total.expense))),
                           innerRadius: .ratio(0.62))
                    .foregroundStyle(colors[index])
            }.frame(height: 170).accessibilityHidden(true)
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                VStack(alignment: .leading, spacing: 5) {
                    Label {
                        Text(entry.name).font(.headline)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(colors[min(index, 7)]).accessibilityHidden(true)
                    }
                    Text(StatisticsDisplay.money(entry.amount, in: report) + " · " + StatisticsDisplay.percent(entry.share))
                    Text("环比 " + StatisticsDisplay.change(entry.change, in: report))
                        .font(.footnote).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
        }
    }

    private func averages(_ report: StatisticsReport) -> some View {
        Section("平均支出") {
            ForEach(report.averages) { average in
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent("\(average.period.rawValue)均", value: StatisticsDisplay.money(average.units, in: report))
                    Text("\(average.count) 个\(average.period.rawValue)周期" + (average.partial ? "，含未满期" : ""))
                        .font(.footnote).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
        }
    }

    private func comparisons(_ report: StatisticsReport) -> some View {
        Section("支出比较") {
            LabeledContent("今日对比昨日", value: StatisticsDisplay.change(report.today, in: report))
            LabeledContent("环比", value: StatisticsDisplay.change(report.previous, in: report))
            LabeledContent("同比", value: StatisticsDisplay.change(report.lastYear, in: report))
        }
    }
}

private struct StatisticsDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    let today: Int64
    let apply: (StatisticsRange) -> Void

    init(initial: StatisticsRange, today: Int64, apply: @escaping (StatisticsRange) -> Void) {
        _start = State(initialValue: StatisticsDisplay.date(initial.days.lowerBound))
        _end = State(initialValue: StatisticsDisplay.date(initial.days.upperBound - 1))
        self.today = today
        self.apply = apply
    }

    var body: some View {
        let range = try? StatisticsRange(start: Self.epochDay(start), endInclusive: Self.epochDay(end))
        NavigationStack {
            Form {
                DatePicker("开始日期", selection: $start, in: ...StatisticsDisplay.date(today), displayedComponents: .date)
                DatePicker("结束日期", selection: $end, in: ...StatisticsDisplay.date(today), displayedComponents: .date)
                if range == nil { Text("请选择最多包含 3,660 天的有效区间。").foregroundStyle(.secondary) }
            }
            .environment(\.calendar, Calendar.utc)
            .environment(\.timeZone, Calendar.utc.timeZone)
            .navigationTitle("自定义期间")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        guard let range else { return }
                        apply(range)
                        dismiss()
                    }.disabled(range == nil)
                }
            }
        }
    }

    private static func epochDay(_ date: Date) -> Int64 {
        Int64(Calendar.utc.startOfDay(for: date).timeIntervalSince1970 / 86_400)
    }
}

enum StatisticsDisplay {
    static func money(_ amount: DecimalInteger, in report: StatisticsReport) -> String {
        PlainDecimal(coefficient: amount, scale: report.scale).text + " " + report.currency.rawValue
    }

    static func money(_ amount: FrozenAmount, currency: CurrencyCode) -> String {
        var text = PlainDecimal(coefficient: amount.units, scale: amount.scale).text
        if amount.scale > 0 {
            while text.last == "0" { text.removeLast() }
            if text.last == "." { text.removeLast() }
        }
        return text + " " + currency.rawValue
    }

    static func percent(_ points: DecimalInteger) -> String { PlainDecimal(coefficient: points, scale: 2).text + "%" }

    static func change(_ change: StatisticsChange, in report: StatisticsReport) -> String {
        guard change.hasData else { return "无可比较数据" }
        let sign = change.magnitude.isZero ? "" : (change.decreases ? "−" : "+")
        let delta = sign + money(change.magnitude, in: report)
        return delta + " · " + (change.basisPoints.map { sign + percent($0) } ?? "百分比不可用")
    }

    static func date(_ epochDay: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(epochDay) * 86_400) }

    static func range(_ days: Range<Int64>) -> String {
        let first = day(days.lowerBound)
        return days.count == 1 ? first : first + " 至 " + day(days.upperBound - 1)
    }

    private static func day(_ epochDay: Int64) -> String {
        let date = GregorianDay(epochDay: epochDay)
        return "\(date.year)/\(date.month)/\(date.day)"
    }

    static func chartUnits(_ amount: DecimalInteger, relativeTo peak: DecimalInteger) -> Int {
        guard !peak.isZero else { return 0 }
        return Int(amount.timesPowerOfTen(6).dividedHalfEven(by: peak).description) ?? 0
    }
}
