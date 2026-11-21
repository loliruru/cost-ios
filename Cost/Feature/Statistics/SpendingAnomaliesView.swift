import SwiftUI

struct SpendingAnomaliesView: View {
    @Bindable var model: StatisticsViewModel
    @State private var confirmClear = false

    var body: some View {
        List {
            if let preferences = model.preferences {
                settings(preferences)
                if !preferences.enabled {
                    Text("异常检测已关闭").accessibilityIdentifier("anomalies.disabled")
                }
                Section("期间") {
                    Picker("期间", selection: $model.anomalyWindow) {
                        ForEach(AnomalyWindow.allCases) { Text("近 \($0.rawValue) 天").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("冻结本位币", value: model.currency.rawValue)
                }
                if preferences.enabled { findings }
                frequencySection
                Section("历史反馈") {
                    Button("清除异常反馈", role: .destructive) { confirmClear = true }.disabled(model.isSavingFeedback)
                }
            } else {
                ProgressView("读取异常设置")
            }
        }
        .navigationTitle("异常开支")
        .task { await model.loadPreferences() }
        .task { await model.loadCoverage() }
        .task(id: model.detectionQuery) { await model.observeAnomalies(model.detectionQuery) }
        .task(id: model.frequencyQuery) { await model.observeFrequency(model.frequencyQuery) }
        .confirmationDialog("清除所有异常反馈？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除异常反馈", role: .destructive) { Task { await model.clearFeedback() } }
        } message: {
            Text("清除后，之前忽略或标记正常的开支可能再次出现。")
        }
        .ledgerError($model.feedbackError)
    }

    private func settings(_ preferences: AnomalyPreferences) -> some View {
        Section {
            Toggle("检测异常开支", isOn: Binding(get: { model.preferences?.enabled ?? preferences.enabled }, set: { enabled in
                var updated = model.preferences ?? preferences
                updated.enabled = enabled
                model.setPreferences(updated)
            })).accessibilityIdentifier("anomalies.enabled")
            if preferences.enabled {
                Picker("灵敏度", selection: Binding(get: { model.preferences?.sensitivity ?? preferences.sensitivity }, set: { sensitivity in
                    var updated = model.preferences ?? preferences
                    updated.sensitivity = sensitivity
                    model.setPreferences(updated)
                })) {
                    ForEach(AnomalySensitivity.allCases) { Text(sensitivityTitle($0)).tag($0) }
                }
            }
        }.disabled(model.isSavingPreferences)
    }

    @ViewBuilder private var findings: some View {
        if model.detectionFailed {
            Text("无法评估异常开支")
            Button("重试") { model.anomalyRetry += 1 }
        } else if let result = model.detection {
            Section("检测结果") {
                switch result.status {
                case .sampleLimit: Text("样本超过 2,000 笔，无法完成检测。")
                case .insufficientData:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("基线数据不足").font(.headline)
                        if let start = model.detectionQuery?.request.start {
                            let cutoff = StatisticsDisplay.range(start..<(start + 1))
                            Text("基线取 \(cutoff) 之前最多 90 天内的非周期支出。")
                        }
                        Text("单笔检测需要同一分类至少 5 笔支出。单日检测需要至少 5 个有支出的日期，单日分类检测按分类分别计数。")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("anomalies.insufficientBaseline")
                case .ready:
                    if result.findings.isEmpty { Text("未发现异常开支") }
                    else { Text("共 \(result.totalFindings) 项，显示最近 \(result.findings.count) 项") }
                    if result.insufficientGroups > 0 { Text("\(result.insufficientGroups) 组基线不足，未参与检测。") }
                    ForEach(AnomalyKind.allCases, id: \.self) { kind in
                        if let counts = result.sampleCounts[kind] {
                            let count = counts.lowerBound == counts.upperBound ? "\(counts.lowerBound)" :
                                "\(counts.lowerBound)–\(counts.upperBound)"
                            let unit = kind == .transaction ? "笔" : "日"
                            let note = counts.lowerBound < 10 ? " · 含样本较少的基线" : ""
                            Text("\(kindTitle(kind))基线 \(count) \(unit)\(note)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(result.findings) { finding in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(findingTitle(finding)).font(.headline)
                        if finding.isProvisional {
                            Text("今日累计 · 临时")
                                .accessibilityIdentifier("anomalies.provisional")
                        }
                        Text(StatisticsDisplay.range(finding.day..<(finding.day + 1)))
                        Text(StatisticsDisplay.money(finding.amount, currency: finding.currency)).font(.headline)
                        let threshold = StatisticsDisplay.money(finding.threshold, currency: finding.currency)
                        Text(finding.thresholdIsApproximate ? "阈值约 \(threshold)" : "阈值 \(threshold)")
                        let note = finding.activeSamples < 10 ? " · 样本较少" : ""
                        Text("\(finding.baselineDays) 天基线 · \(finding.activeSamples) 个有效样本\(note)")
                            .foregroundStyle(.secondary)
                        Menu("反馈") {
                            Button("忽略本次") { Task { await model.saveFeedback(.ignoredOnce, for: finding) } }
                            Button("标记相似开支为正常") { Task { await model.saveFeedback(.markedNormal, for: finding) } }
                        }.disabled(model.isSavingFeedback)
                    }
                }
            }
        } else {
            ProgressView("评估异常开支")
        }
    }

    private var frequencySection: some View {
        Section("支出频率") {
            if model.coverageLoadFailed {
                Text("无法读取记账覆盖")
                Button("重试读取覆盖") { Task { await model.loadCoverage() } }
            } else if let today = model.today, model.coverage != nil {
                NavigationLink("管理记账覆盖") { RecordingCoverageView(model: model, today: today) }
                    .accessibilityIdentifier("coverage.open")
            }

            if model.frequencyFailed {
                Text("无法读取支出频率")
                Button("重试读取频率") { model.frequencyRetry += 1 }
            } else if let frequency = model.frequency {
                frequencyRow("近期", frequency.recent, id: "frequency.recent")
                frequencyRow("历史", frequency.history, id: "frequency.history")
                ForEach(frequency.issues.indices, id: \.self) { index in
                    Text(coverageIssue(frequency.issues[index]))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if !model.coverageLoadFailed {
                ProgressView("读取支出频率")
            }
        }
    }

    private func frequencyRow(_ title: String, _ period: SpendingFrequency.Period, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(StatisticsDisplay.range(period.days)).font(.footnote).foregroundStyle(.secondary)
            Text("\(period.spendingDays) 个支出日 · \(period.coveredDays) 个覆盖日")
            Text(period.basisPoints.map(StatisticsDisplay.percent) ?? "暂无比例")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func coverageIssue(_ issue: SpendingFrequency.CoverageIssue) -> String {
        switch issue {
        case .unconfirmed: "请确认记账覆盖。频率使用已确认的完整日期。"
        case .tooFewRecent(let required): "近期覆盖不足，参考至少需要 \(required) 个完整日。"
        case .tooFewHistorical: "历史覆盖不足，参考至少需要 28 个完整日。"
        case .missingWeekdays: "历史中部分对应星期几的覆盖不足 3 次。"
        }
    }

    private func kindTitle(_ kind: AnomalyKind) -> String {
        switch kind {
        case .transaction: "单笔"
        case .day: "单日总额"
        case .category: "单日分类"
        }
    }

    private func findingTitle(_ finding: AnomalyFinding) -> String {
        switch finding.kind {
        case .transaction: "单笔支出 · " + (finding.categoryName ?? "分类")
        case .day: "单日总支出"
        case .category: "单日分类支出 · " + (finding.categoryName ?? "分类")
        }
    }

    private func sensitivityTitle(_ sensitivity: AnomalySensitivity) -> String {
        switch sensitivity {
        case .low: "低"
        case .normal: "标准"
        case .high: "高"
        }
    }
}

private struct RecordingCoverageView: View {
    @Bindable var model: StatisticsViewModel
    @State private var start: Date
    @State private var historicalDay: Date

    init(model: StatisticsViewModel, today: Int64) {
        self.model = model
        _start = State(initialValue: StatisticsDisplay.date(today + 1))
        _historicalDay = State(initialValue: StatisticsDisplay.date(today - 1))
    }

    var body: some View {
        Form {
            if let coverage = model.coverage, let today = model.today {
                Section("记账期间") {
                    if let activeStart = coverage.activeStart {
                        let date = StatisticsDisplay.range(activeStart..<(activeStart + 1))
                        Text(activeStart > today ? "将于 \(date) 开始" : "覆盖自 \(date) 开始")
                            .accessibilityIdentifier("coverage.active")
                        Button("暂停覆盖") { save(.pause) }
                            .accessibilityIdentifier("coverage.pause")
                        Text("暂停从今日生效。").font(.footnote).foregroundStyle(.secondary)
                    } else if coverage.hasStarted {
                        Text("覆盖已暂停").accessibilityIdentifier("coverage.paused")
                        Button("从明日恢复覆盖") { save(.resume) }
                            .accessibilityIdentifier("coverage.resume")
                    } else {
                        DatePicker("开始日期", selection: $start, in: ...StatisticsDisplay.date(today + 1), displayedComponents: .date)
                        Button("确认开始覆盖") {
                            if let day = epochDay(start) { save(.start(day)) }
                        }.accessibilityIdentifier("coverage.start")
                        Text("请选择开始完整记账的日期。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("历史日期") {
                    DatePicker("日期", selection: $historicalDay, in: ...StatisticsDisplay.date(today - 1), displayedComponents: .date)
                    if let day = epochDay(historicalDay) {
                        Text(coverage.contains(day) ? "该日已确认覆盖" : "该日覆盖未知")
                            .accessibilityIdentifier("coverage.selectedDay")
                        Button("确认该日完整记账") { save(.confirmDay(day)) }
                            .accessibilityIdentifier("coverage.confirmDay")
                        Button("将该日标为未知") { save(.markUnknown(day)) }
                            .accessibilityIdentifier("coverage.markUnknown")
                    }
                }
            }
        }
        .disabled(model.isSavingCoverage)
        .environment(\.calendar, Calendar.utc)
        .environment(\.timeZone, Calendar.utc.timeZone)
        .navigationTitle("记账覆盖")
        .ledgerError($model.coverageError)
    }

    private func save(_ action: RecordingCoverage.Action) {
        Task { await model.updateCoverage(action) }
    }

    private func epochDay(_ date: Date) -> Int64? {
        Calendar.utc.dateComponents([.year, .month, .day], from: date).dateEpochDay
    }
}
