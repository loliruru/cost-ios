import SwiftUI

struct RecurringRulesView: View {
    @Bindable var model: RecurringViewModel
    @State private var editor: RecurringEditorRoute?
    @State private var skipping: RecurringExecution?

    var body: some View {
        List {
            Section {
                Toggle("到期本地提醒", isOn: Binding(get: { model.remindersEnabled }, set: { enabled in
                    Task { await model.setReminders(enabled) }
                })).disabled(model.isBusy)
            } footer: {
                Text("系统安排后台执行时间。打开 Cost 时会按补记策略处理到期账单。")
            }
            if model.rows.isEmpty {
                ContentUnavailableView("暂无周期规则", systemImage: "calendar.badge.clock")
            } else {
                Section("周期规则") {
                    ForEach(model.rows) { rule in
                        Button { editor = RecurringEditorRoute(rule: rule) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.content.name).font(.headline)
                                Text("\(rule.content.amount.plainText) \(rule.content.amount.currencyCode.rawValue) · \(rule.content.schedule.frequency.title)")
                                Text(status(for: rule)).font(.footnote).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("recurring.rule.\(rule.id)")
                    }
                }
            }
            if !model.failures.isEmpty {
                Section("待处理") {
                    ForEach(model.failures) { execution in failureRow(execution) }
                    if model.hasMoreFailures { Button("加载更多") { Task { await model.loadMoreFailures() } }.disabled(model.isBusy) }
                }
            }
        }
        .navigationTitle("周期记账")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新增规则", systemImage: "plus") { editor = RecurringEditorRoute(rule: nil) }
                    .accessibilityIdentifier("recurring.add")
            }
        }
        .task { await model.ledger.reload(); await model.reload() }
        .refreshable { await model.run() }
        .sheet(item: $editor) { route in RecurringEditorView(model: model, rule: route.rule) }
        .confirmationDialog("跳过这次周期账单？", isPresented: Binding(get: { skipping != nil }, set: { if !$0 { skipping = nil } }),
                            titleVisibility: .visible, presenting: skipping) { execution in
            Button("跳过本次", role: .destructive) { Task { await model.resolve(execution, skipping: true) } }
        }
        .ledgerError($model.error)
    }

    private func status(for rule: RecurringRule) -> String {
        guard rule.isEnabled else { return "已暂停" }
        guard let next = rule.nextOccurrence else { return "已结束" }
        return "下次计划 \(plannedTime(next, zoneID: rule.content.schedule.zoneID))"
    }

    private func failureRow(_ execution: RecurringExecution) -> some View {
        let rule = model.rows.first { $0.id == execution.ruleID }
        return VStack(alignment: .leading, spacing: 6) {
            Text(rule?.content.name ?? "周期账单").font(.headline)
            Text(plannedTime(execution.scheduledAt, zoneID: rule?.content.schedule.zoneID ?? "UTC"))
            if let issue = execution.issue { Text(model.message(for: issue)).font(.footnote).foregroundStyle(.secondary) }
            if rule?.isEnabled == false { Text("恢复规则后可重试。").font(.footnote).foregroundStyle(.secondary) }
            Button("重试本次") { Task { await model.resolve(execution, skipping: false) } }
                .buttonStyle(.borderless).disabled(model.isBusy || rule?.isEnabled != true)
            Button("跳过本次", role: .destructive) { skipping = execution }
                .buttonStyle(.borderless).disabled(model.isBusy)
        }
    }

    private func plannedTime(_ instant: Int64, zoneID: String) -> String {
        guard let occurred = try? OccurredAt(epochMillis: instant, zoneID: zoneID) else { return zoneID }
        return LedgerStyle.occurred(occurred)
    }
}

private struct RecurringEditorRoute: Identifiable {
    let id = UUID()
    let rule: RecurringRule?
}

private struct RecurringEditorView: View {
    private enum Confirmation { case resume, delete }

    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RecurringViewModel
    let rule: RecurringRule?
    @State private var draft: RecurringDraft
    @State private var intervalText: String
    @State private var confirm: Confirmation?
    @State private var selectingZone = false
    @State private var zoneSearch = ""

    init(model: RecurringViewModel, rule: RecurringRule?) {
        self.model = model
        self.rule = rule
        let draft = model.draft(for: rule)
        _draft = State(initialValue: draft)
        _intervalText = State(initialValue: String(draft.schedule.intervalValue))
    }

    var body: some View {
        NavigationStack {
            Form {
                contentFields
                scheduleFields
                noteAndTags
                if let rule { ruleActions(rule) }
            }
            .disabled(model.isBusy)
            .navigationTitle(rule == nil ? "新增周期规则" : "编辑周期规则")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(model.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(model.isBusy || draft.name.isEmpty || draft.amount.isEmpty)
                        .accessibilityIdentifier("recurring.save")
                }
            }
            .onChange(of: draft.type) { _, _ in draft.categoryID = model.categories(for: draft).first?.id ?? "" }
            .onChange(of: draft.schedule.startDay) { _, day in
                if let end = draft.schedule.endDay, end < day { draft.schedule.endDay = day }
            }
            .sheet(isPresented: $selectingZone) { zones }
            .confirmationDialog(confirm == .delete ? "删除此规则？已生成的账单会保留。" : "如何处理暂停期间的账单？",
                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible,
                presenting: confirm) { option in
                    if option == .delete {
                        Button("确认删除", role: .destructive) { Task { if let rule, await model.delete(rule) { dismiss() } } }
                            .accessibilityIdentifier("recurring.confirmDelete")
                    } else {
                        Button("补记已错过账单") { resume(.createMissed) }
                        Button("跳过已错过账单") { resume(.skipMissed) }
                    }
                }
            .interactiveDismissDisabled(model.isBusy)
            .ledgerError($model.error)
        }
    }

    private var contentFields: some View {
        Section("记账内容") {
            TextField("规则名称", text: $draft.name).accessibilityIdentifier("recurring.name")
            Picker("收支", selection: $draft.type) {
                Text("支出").tag(TransactionType.expense)
                Text("收入").tag(TransactionType.income)
            }
            TextField("金额", text: $draft.amount).keyboardType(.decimalPad).accessibilityIdentifier("recurring.amount")
            Picker("币种", selection: $draft.currencyCode) {
                if !model.ledger.currencies.contains(where: { $0.assetType == .fiat && $0.code.rawValue == draft.currencyCode }) {
                    Text(draft.currencyCode).tag(draft.currencyCode)
                }
                ForEach(model.ledger.currencies.filter { $0.assetType == .fiat }, id: \.code) {
                    Text("\($0.code.rawValue) \($0.displayName)").tag($0.code.rawValue)
                }
            }
            Picker("分类", selection: $draft.categoryID) {
                Text("请选择").tag("")
                ForEach(model.categories(for: draft, keeping: rule?.content.categoryID), id: \.id) { Text($0.name).tag($0.id) }
            }
            Picker("账户", selection: $draft.accountID) {
                Text("请选择").tag("")
                ForEach(model.ledger.accounts.filter { !$0.isArchived || $0.id == rule?.content.accountID }, id: \.id) { Text($0.name).tag($0.id) }
            }
        }
    }

    private var scheduleFields: some View {
        Section("计划") {
            Picker("频率", selection: $draft.schedule.frequency) {
                ForEach(RecurringFrequency.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            frequencyFields
            LabeledContent("时区") { Button(draft.schedule.zoneID) { selectingZone = true } }
            DatePicker("开始日期", selection: dayBinding(end: false), displayedComponents: .date)
            Toggle("设置结束日期", isOn: Binding(get: { draft.schedule.endDay != nil }, set: {
                draft.schedule.endDay = $0 ? draft.schedule.startDay : nil
            }))
            if draft.schedule.endDay != nil {
                DatePicker("结束日期（包含当天）", selection: dayBinding(end: true), in: wallDate(draft.schedule.startDay)..., displayedComponents: .date)
            }
            DatePicker("当地时间", selection: Binding(get: { Date(timeIntervalSince1970: TimeInterval(draft.schedule.minutes * 60)) }, set: {
                let components = Calendar.utc.dateComponents([.hour, .minute], from: $0)
                draft.schedule.minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
            Picker("补记策略", selection: $draft.catchUp) {
                Text("补记已错过账单").tag(RecurringCatchUp.createMissed)
                Text("跳过过去日期").tag(RecurringCatchUp.skipMissed)
            }
        }
        .environment(\.calendar, Calendar.utc)
        .environment(\.timeZone, Calendar.utc.timeZone)
    }

    @ViewBuilder private var frequencyFields: some View {
        if draft.schedule.frequency == .weeklySet {
            let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
            ForEach(weekdays.indices, id: \.self) { index in
                let mask = 1 << index
                Toggle(weekdays[index], isOn: Binding(get: { draft.schedule.weekdaysMask & mask != 0 }, set: { enabled in
                    if enabled { draft.schedule.weekdaysMask |= mask }
                    else { draft.schedule.weekdaysMask &= ~mask }
                }))
            }
        }
        if draft.schedule.frequency == .yearly {
            Picker("月份", selection: Binding(get: { draft.schedule.monthOfYear ?? 1 }, set: { draft.schedule.monthOfYear = $0 })) {
                ForEach(1...12, id: \.self) { Text("\($0) 月").tag($0) }
            }
        }
        if [.monthly, .yearly].contains(draft.schedule.frequency) {
            Picker("日期", selection: Binding(get: { draft.schedule.dayOfMonth ?? 1 }, set: { draft.schedule.dayOfMonth = $0 })) {
                ForEach(1...31, id: \.self) { Text("\($0) 日").tag($0) }
            }
        }
        if draft.schedule.frequency == .interval {
            TextField("间隔次数", text: $intervalText).keyboardType(.numberPad)
            Picker("间隔单位", selection: Binding(get: { draft.schedule.intervalUnit ?? .day }, set: { draft.schedule.intervalUnit = $0 })) {
                ForEach(RecurringIntervalUnit.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        if [.monthly, .yearly].contains(draft.schedule.frequency) ||
            (draft.schedule.frequency == .interval && (draft.schedule.intervalUnit == .month || draft.schedule.intervalUnit == .year)) {
            Picker("该月没有指定日期时", selection: $draft.schedule.monthPolicy) {
                Text("安排到月末").tag(RecurringMonthPolicy.lastDay)
                Text("跳过该月").tag(RecurringMonthPolicy.skip)
            }
        }
    }

    private var noteAndTags: some View {
        Section("备注和标签") {
            TextField("备注", text: $draft.note, axis: .vertical)
            ForEach(model.ledger.tags.filter { !$0.isArchived || rule?.content.tagIDs.contains($0.id) == true }, id: \.id) { tag in
                Toggle(tag.name, isOn: Binding(get: { draft.tagIDs.contains(tag.id) }, set: { selected in
                    if selected { draft.tagIDs.insert(tag.id) } else { draft.tagIDs.remove(tag.id) }
                }))
            }
        }
    }

    private func ruleActions(_ rule: RecurringRule) -> some View {
        Section {
            Button(rule.isEnabled ? "暂停规则" : "恢复规则") {
                if rule.isEnabled {
                    Task { if await model.setEnabled(rule, enabled: false, catchUp: rule.content.catchUp) { dismiss() } }
                } else { confirm = .resume }
            }
            Button("删除规则", role: .destructive) { confirm = .delete }
        }
    }

    private var zones: some View {
        let choices = ["UTC"] + TimeZone.knownTimeZoneIdentifiers.filter { $0 != "UTC" }
        return NavigationStack {
            List(choices.filter { zoneSearch.isEmpty || $0.localizedCaseInsensitiveContains(zoneSearch) }, id: \.self) { zone in
                Button(zone) { draft.schedule.zoneID = zone; selectingZone = false }
            }
            .navigationTitle("选择时区")
            .searchable(text: $zoneSearch, prompt: "搜索城市或时区 ID")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { selectingZone = false } } }
        }
    }

    private func dayBinding(end: Bool) -> Binding<Date> {
        Binding(get: { wallDate(end ? draft.schedule.endDay ?? draft.schedule.startDay : draft.schedule.startDay) }, set: { date in
            let day = Int64(floor(date.timeIntervalSince1970 / 86400))
            if end { draft.schedule.endDay = day } else { draft.schedule.startDay = day }
        })
    }

    private func wallDate(_ day: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86400) }

    private func save() async {
        var content = draft
        if content.schedule.frequency == .interval {
            content.schedule.intervalValue = Int(intervalText) ?? 0
            content.schedule.intervalUnit = content.schedule.intervalUnit ?? .day
        }
        if [.monthly, .yearly].contains(content.schedule.frequency) { content.schedule.dayOfMonth = content.schedule.dayOfMonth ?? 1 }
        if content.schedule.frequency == .yearly { content.schedule.monthOfYear = content.schedule.monthOfYear ?? 1 }
        if await model.save(content, editing: rule) { dismiss() }
    }

    private func resume(_ policy: RecurringCatchUp) {
        guard let rule else { return }
        Task { if await model.setEnabled(rule, enabled: true, catchUp: policy) { dismiss() } }
    }
}

private extension RecurringFrequency {
    var title: String {
        switch self {
        case .daily: "每天"
        case .weekdays: "每个工作日（周一至周五）"
        case .weeklySet: "指定星期"
        case .monthly: "每月"
        case .yearly: "每年"
        case .interval: "固定间隔"
        }
    }
}

private extension RecurringIntervalUnit {
    var title: String {
        switch self {
        case .day: "天"
        case .week: "周"
        case .month: "月"
        case .year: "年"
        }
    }
}
