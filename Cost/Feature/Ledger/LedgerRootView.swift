import SwiftUI

struct LedgerRootView: View {
    @Bindable var model: LedgerViewModel
    let recurring: RecurringViewModel
    let statistics: StatisticsViewModel
    var portable: PortableDataViewModel?
    private var clearingData: Bool { portable?.resetting == true || portable?.resetPending == true }

    var body: some View {
        TabView {
            Tab("账单", systemImage: "list.bullet.rectangle") {
                LedgerListView(model: model).costTabChrome()
            }
            Tab("模板", systemImage: "square.on.square") {
                QuickTemplatesView(ledger: model).id(portable?.resetRevision).costTabChrome()
            }
            Tab("统计", systemImage: "chart.bar.xaxis") {
                StatisticsView(model: statistics).costTabChrome()
            }
            Tab("设置", systemImage: "gearshape") {
                LedgerSettingsView(model: model, recurring: recurring, portable: portable).costTabChrome()
            }
        }
        .disabled(clearingData)
        .accessibilityHidden(clearingData)
        .overlay {
            if let portable, clearingData {
                VStack(spacing: 16) {
                    if portable.resetting {
                        ProgressView("正在清空本机数据…")
                    } else {
                        Text("账本已清空，仍有本机资料待清理。")
                        Button("继续清理") { Task { await portable.resetLocalData() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { Rectangle().fill(.background).ignoresSafeArea() }
            }
        }
        .task { await model.reload() }
        .onChange(of: model.baseCurrency?.code) { _, code in
            if let code { statistics.updateDefaultCurrency(code) }
        }
        .ledgerError($model.error)
    }
}

struct LedgerSettingsView: View {
    @Bindable var model: LedgerViewModel
    let recurring: RecurringViewModel
    var portable: PortableDataViewModel?
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            List {
                metadataSection
                fundsSection
                NavigationLink {
                    RecurringRulesView(model: recurring)
                } label: {
                    Label("周期记账", systemImage: "calendar.badge.clock")
                }.accessibilityIdentifier("recurring.open")
                Section("多币种") {
                    NavigationLink { CurrencySettingsView(ledger: model) } label: {
                        Label("币种与报价", systemImage: "arrow.left.arrow.right.circle")
                    }.accessibilityIdentifier("settings.quotes")
                }
                if let portable {
                    NavigationLink { PortableDataView(model: portable) } label: {
                        Label("导入与备份", systemImage: "externaldrive")
                    }.accessibilityIdentifier("settings.portable")
                    Section {
                        Button("清空所有数据", systemImage: "trash", role: .destructive) { confirmingReset = true }
                            .disabled(portable.busy)
                            .accessibilityIdentifier("settings.resetData")
                        if portable.resetRevision > 0, model.categories.isEmpty, model.accounts.isEmpty {
                            Text("清空完成。记账前请先新增分类和账户。")
                                .accessibilityIdentifier("settings.resetComplete")
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .costNavigationChrome()
            .alert("清空所有数据？", isPresented: $confirmingReset) {
                Button("取消", role: .cancel) {}
                Button("确认清空", role: .destructive) {
                    Task { await portable?.resetLocalData() }
                }.accessibilityIdentifier("settings.confirmReset")
            } message: {
                Text("这会永久删除本机账单、全部分类和账户、模板、周期规则、图片、草稿和设置，并移除行情 API Key。内置币种会恢复初始状态。需要保留的资料请先导出完整备份。")
            }
            .alert("无法完成清空", isPresented: Binding(
                get: { portable?.resetError != nil }, set: { if !$0 { portable?.resetError = nil } }
            )) {
                Button("好", role: .cancel) { portable?.resetError = nil }
            } message: {
                Text(portable?.resetError ?? "")
            }
        }
    }
    private var metadataSection: some View {
        Section("基础资料") {
            NavigationLink { MetadataListView(ledger: model, kind: .category) } label: { Label("分类", systemImage: "square.grid.2x2") }
            NavigationLink { MetadataListView(ledger: model, kind: .account) } label: { Label("账户", systemImage: "wallet.bifold") }
            NavigationLink { MetadataListView(ledger: model, kind: .tag) } label: { Label("标签", systemImage: "tag") }
        }
    }
    private var fundsSection: some View {
        Section("可选账户资金") {
            NavigationLink { FundsListView(ledger: model) } label: { Label("资金起点与本金转账", systemImage: "arrow.left.arrow.right") }
            Text("资金追踪默认关闭。未设置金额与零余额有区别。开启或校准只从保存时点开始计算。").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct LedgerListView: View {
    @Bindable var model: LedgerViewModel
    @State private var showEntry = false
    @State private var showFilters = false
    @State private var detail: LedgerTransaction?
    @AccessibilityFocusState(for: .voiceOver) private var addFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private var days: [Int64] { Set(model.rows.map { $0.occurredAt.localEpochDay }).sorted(by: >) }
    var body: some View {
        NavigationStack {
            List {
                if let notice = model.notice {
                    Section {
                        Text(notice).font(.callout)
                        if let id = model.undoID { Button("撤销删除") { restore(id: id) }.disabled(model.isBusy) }
                    }
                }
                if model.rows.isEmpty {
                    ContentUnavailableView(model.query.deletedOnly ? "没有已删除账单" : "暂无账单", systemImage: "tray",
                        description: Text(model.query.deletedOnly ? "可调整搜索和筛选条件。" : "轻点「记一笔」新增账单，或调整搜索和筛选条件。"))
                }
                ForEach(days, id: \.self) { day in
                    Section(LedgerStyle.day(day)) {
                        ForEach(model.rows.filter { $0.occurredAt.localEpochDay == day }, id: \.id) { row in
                            Button { detail = row } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    LedgerIcon(visual: model.categories.first { $0.id == row.categoryID }?.visual ?? LedgerVisual(), repository: model.services.visuals)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(model.categoryName(row.categoryID)).foregroundStyle(.primary)
                                        Text(LedgerStyle.amount(row)).font(.headline).monospacedDigit().foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                                        Text(model.accountName(row.accountID)).font(.caption).foregroundStyle(.secondary)
                                    if let note = row.note {
                                        Text(note).font(.subheadline).foregroundStyle(.secondary)
                                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                    }
                                    }
                                    Spacer(minLength: 0)
                                    if !typeSize.isAccessibilitySize {
                                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary).accessibilityHidden(true)
                                    }
                                }
                            }
                            .accessibilityLabel(rowLabel(row))
                            .accessibilityIdentifier("ledger.row.\(row.id)")
                            .swipeActions {
                                if row.deletedAt == nil {
                                    Button("删除", systemImage: "trash", role: .destructive) { delete(row) }
                                } else {
                                    Button("恢复", systemImage: "arrow.uturn.backward") { restore(id: row.id) }.tint(.accentColor)
                                }
                            }
                        }
                    }
                }
                if model.nextCursor != nil { Button("加载更多账单") { Task { await model.loadMore() } }.disabled(model.isBusy) }
            }
            .animation(CostMotion.ledgerChange(reduceMotion: reduceMotion), value: model.undoID)
            .navigationTitle(model.query.deletedOnly ? "已删除账单" : "账单")
            .costNavigationChrome()
            .searchable(text: $model.query.text, prompt: "备注、分类、账户或标签")
            .refreshable { await model.reload() }
            .task(id: model.query) { await model.reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("筛选", systemImage: "line.3.horizontal.decrease") { showFilters = true } }
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                CostEntryButton { showEntry = true }
                    .accessibilityIdentifier("ledger.add")
                    .accessibilityFocused($addFocused)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .sheet(isPresented: $showEntry, onDismiss: {
                addFocused = true
                Task { await model.reload() }
            }) {
                EntryView(ledger: model).costEntrySheet()
            }
            .sheet(isPresented: $showFilters) { LedgerFilterView(model: model) }
            .sheet(item: $detail, onDismiss: { Task { await model.reload() } }) { row in LedgerDetailView(ledger: model, row: row) }
        }
    }

    private func rowLabel(_ row: LedgerTransaction) -> String {
        var parts = [row.type == .expense ? "支出" : "收入", LedgerStyle.amount(row),
            model.categoryName(row.categoryID), model.accountName(row.accountID)]
        if let note = row.note, !note.isEmpty { parts.append(note) }
        if row.deletedAt != nil { parts.append("已删除") }
        return parts.joined(separator: "，")
    }

    private func delete(_ row: LedgerTransaction) {
        Task {
            if await model.delete(row) { CostHaptics.success() }
        }
    }

    private func restore(id: String) {
        Task {
            if await model.restore(id: id) { CostHaptics.success() }
        }
    }
}

extension LedgerTransaction: Identifiable {}

struct LedgerFilterView: View {
    @Bindable var model: LedgerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var dateEnabled = false
    @State private var start = Date()
    @State private var end = Date()
    var body: some View {
        NavigationStack {
            Form {
                Picker("收支", selection: $model.query.type) {
                    Text("全部").tag(nil as TransactionType?)
                    Text("支出").tag(TransactionType.expense as TransactionType?)
                    Text("收入").tag(TransactionType.income as TransactionType?)
                }
                Picker("分类（含子分类）", selection: $model.query.categoryID) {
                    Text("全部").tag(nil as String?)
                    ForEach(model.categories, id: \.id) { Text($0.name).tag($0.id as String?) }
                }
                Picker("账户", selection: $model.query.accountID) {
                    Text("全部").tag(nil as String?)
                    ForEach(model.accounts, id: \.id) { Text($0.name).tag($0.id as String?) }
                }
                Picker("标签", selection: $model.query.tagID) {
                    Text("全部").tag(nil as String?)
                    ForEach(model.tags, id: \.id) { Text($0.name).tag($0.id as String?) }
                }
                Toggle("查看已删除账单", isOn: $model.query.deletedOnly)
                    .accessibilityIdentifier("ledger.filter.deleted")
                Section("按冻结业务日期筛选") {
                    Toggle("限定日期", isOn: $dateEnabled)
                    if dateEnabled {
                        DatePicker("开始", selection: $start, displayedComponents: .date).environment(\.calendar, Calendar.localGregorian)
                        DatePicker("结束（包含当天）", selection: $end, in: start..., displayedComponents: .date).environment(\.calendar, Calendar.localGregorian)
                    }
                }
                Button("重置筛选") { model.query = LedgerQuery(); dateEnabled = false }
            }
            .navigationTitle("筛选")
            .costNavigationChrome()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") {
                model.query.startDay = dateEnabled ? Calendar.localGregorian.dateComponents([.year, .month, .day], from: start).dateEpochDay : nil
                model.query.endDayExclusive = dateEnabled ? Calendar.localGregorian.dateComponents([.year, .month, .day], from: end).dateEpochDay.map { $0 + 1 } : nil
                dismiss()
            } } }
        }
        .onAppear {
            dateEnabled = model.query.startDay != nil
            if let day = model.query.startDay { start = Calendar.localGregorian.date(from: Calendar.utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(day) * 86400))) ?? Date() }
            if let day = model.query.endDayExclusive { end = Calendar.localGregorian.date(from: Calendar.utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(day - 1) * 86400))) ?? Date() }
        }
    }
}

extension Calendar {
    static var utc: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar }
    static var localGregorian: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current; return calendar }
}
extension DateComponents {
    var dateEpochDay: Int64? { Calendar.utc.date(from: self).map { Int64($0.timeIntervalSince1970 / 86400) } }
}

struct LedgerDetailView: View {
    @Bindable var ledger: LedgerViewModel
    let row: LedgerTransaction
    @State private var managed = false
    @State private var checked = false
    @State private var editing = false
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let visual = ledger.categories.first(where: { $0.id == row.categoryID })?.visual, let id = visual.backgroundAssetID {
                        ManagedPicture(id: id, repository: ledger.services.visuals, focus: visual.backgroundFocus).frame(height: 160).clipShape(.rect(cornerRadius: 12))
                    }
                    Text(LedgerStyle.amount(row)).font(.largeTitle).monospacedDigit().textSelection(.enabled)
                    CostValueRow("类型", value: row.type == .expense ? "支出" : "收入")
                    CostValueRow("分类", value: ledger.categoryName(row.categoryID))
                    CostValueRow("账户", value: ledger.accountName(row.accountID))
                    CostValueRow("业务日期", value: LedgerStyle.day(row.occurredAt.localEpochDay))
                    CostValueRow("时区", value: row.occurredAt.zoneID)
                    Text(LedgerStyle.occurred(row.occurredAt))
                    if let note = row.note { Text(note).textSelection(.enabled) }
                    if !row.tagIDs.isEmpty { Text(ledger.tags.filter { row.tagIDs.contains($0.id) }.map(\.name).joined(separator: "、")) }
                }
                Section("冻结估值") {
                    CostValueRow("本位币金额", value: row.convertedBase.plainText + " " + row.convertedBase.currencyCode.rawValue)
                        .accessibilityIdentifier("ledger.frozenBase")
                    FrozenQuoteRows(snapshot: row.exchangeRate, venue: row.crypto?.venue)
                }
                if managed {
                    Text("这笔损益随本金转账保存和撤销。请在设置 → 资金起点与本金转账中操作。")
                } else if checked {
                    if row.deletedAt != nil {
                        Button("恢复账单") {
                            Task {
                                if await ledger.restore(id: row.id) {
                                    CostHaptics.success()
                                    dismiss()
                                }
                            }
                        }
                    }
                    else {
                        Button("删除账单", role: .destructive) { deleting = true }
                    }
                }
            }
            .navigationTitle("账单详情")
            .navigationBarTitleDisplayMode(.inline)
            .costNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                if checked && !managed && row.deletedAt == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("编辑账单", systemImage: "pencil") { editing = true }
                            .accessibilityIdentifier("ledger.edit")
                    }
                }
            }
            .sheet(isPresented: $editing, onDismiss: { dismiss() }) {
                EntryView(ledger: ledger, existing: row).costEntrySheet()
            }
            .confirmationDialog("删除后可撤销，也可从已删除账单恢复。", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    Task {
                        if await ledger.delete(row) {
                            CostHaptics.success()
                            dismiss()
                        }
                    }
                }
                .accessibilityIdentifier("ledger.confirmDelete")
            }
            .disabled(ledger.isBusy)
            .task {
                if let result = await ledger.managed(id: row.id) { managed = result; checked = true }
            }
        }
    }
}
