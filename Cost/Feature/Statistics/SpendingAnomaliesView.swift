import SwiftUI

struct SpendingAnomaliesView: View {
    @Bindable var model: StatisticsViewModel
    @State private var confirmClear = false

    var body: some View {
        List {
            if let preferences = model.preferences {
                settings(preferences)
                if preferences.enabled {
                    Section("候选期间") {
                        Picker("候选期间", selection: $model.anomalyWindow) {
                            ForEach(AnomalyWindow.allCases) { Text("近 \($0.rawValue) 天").tag($0) }
                        }.pickerStyle(.segmented)
                        LabeledContent("冻结本位币", value: model.currency.rawValue)
                    }
                    findings
                } else {
                    Text("异常检测已关闭").accessibilityIdentifier("anomalies.disabled")
                }
                Section("历史反馈") {
                    Button("清除异常反馈", role: .destructive) { confirmClear = true }.disabled(model.isSavingFeedback)
                }
            } else {
                ProgressView("读取异常设置")
            }
        }
        .navigationTitle("异常开支")
        .task { await model.loadPreferences() }
        .task(id: model.detectionQuery) { await model.observeAnomalies(model.detectionQuery) }
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
                case .insufficientData: Text("基线数据不足，至少需要 5 笔或 5 个活跃日。")
                case .ready:
                    if result.findings.isEmpty { Text("未发现异常开支") }
                    else { Text("共 \(result.totalFindings) 项，显示最近 \(result.findings.count) 项") }
                    if result.insufficientGroups > 0 { Text("\(result.insufficientGroups) 组基线不足，未参与检测。") }
                }
                ForEach(result.findings) { finding in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(findingTitle(finding)).font(.headline)
                        Text(StatisticsDisplay.range(finding.day..<(finding.day + 1)))
                        Text(StatisticsDisplay.money(finding.amount, currency: finding.currency)).font(.headline)
                        Text("阈值 \(StatisticsDisplay.money(finding.threshold, currency: finding.currency))")
                        Text("\(finding.baselineDays) 天基线 · \(finding.activeSamples) 个有效样本")
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
