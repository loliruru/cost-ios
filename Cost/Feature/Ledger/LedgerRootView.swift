import SwiftUI

struct LedgerRootView: View {
    @Bindable var model: LedgerViewModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            LedgerListView(model: model).tabItem { Label("账单", systemImage: "list.bullet.rectangle") }
            LedgerSettingsView(model: model).tabItem { Label("设置", systemImage: "gearshape") }
        }
        .task { await model.reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.reload() } } }
        .ledgerError($model.error)
    }
}

struct LedgerSettingsView: View {
    @Bindable var model: LedgerViewModel
    var body: some View {
        NavigationStack {
            List {
                metadataSection
                fundsSection
                Section("当前版本") {
                    LabeledContent("本位币", value: "CNY")
                    Text("支持离线本币记账。多币种估值、模板、循环与统计按后续阶段提供。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("设置")
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
    private var days: [Int64] { Set(model.rows.map { $0.occurredAt.localEpochDay }).sorted(by: >) }
    var body: some View {
        NavigationStack {
            List {
                if let notice = model.notice {
                    Section {
                        Text(notice).font(.callout)
                        if let id = model.undoID { Button("撤销删除") { Task { await model.restore(id: id) } }.disabled(model.isBusy) }
                    }
                }
                if model.rows.isEmpty {
                    ContentUnavailableView(model.query.deletedOnly ? "没有已删除账单" : "暂无账单", systemImage: "tray", description: Text("点击右上角加号记一笔，或调整搜索和筛选条件。"))
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
                                        if let note = row.note { Text(note).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                                }
                            }
                            .accessibilityLabel("\(row.type == .expense ? "支出" : "收入")，\(LedgerStyle.amount(row))，\(model.categoryName(row.categoryID))，\(model.accountName(row.accountID))，\(row.note ?? "")")
                            .accessibilityIdentifier("ledger.row.\(row.id)")
                            .swipeActions {
                                if row.deletedAt == nil { Button("删除", role: .destructive) { Task { await model.delete(row) } } }
                                else { Button("恢复") { Task { await model.restore(id: row.id) } }.tint(.green) }
                            }
                        }
                    }
                }
                if model.nextCursor != nil { Button("加载更多账单") { Task { await model.loadMore() } }.disabled(model.isBusy) }
            }
            .navigationTitle(model.query.deletedOnly ? "已删除账单" : "账单")
            .searchable(text: $model.query.text, prompt: "备注、分类、账户或标签")
            .refreshable { await model.reload() }
            .task(id: model.query) { await model.reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("筛选", systemImage: "line.3.horizontal.decrease") { showFilters = true } }
                ToolbarItem(placement: .topBarTrailing) { Button("记一笔", systemImage: "plus") { showEntry = true }.accessibilityIdentifier("ledger.add") }
            }
            .sheet(isPresented: $showEntry, onDismiss: { Task { await model.reload() } }) {
                EntryView(ledger: model).presentationDetents([.large])
            }
            .sheet(isPresented: $showFilters) { LedgerFilterView(model: model) }
            .sheet(item: $detail, onDismiss: { Task { await model.reload() } }) { row in LedgerDetailView(ledger: model, row: row) }
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
                    LabeledContent("类型", value: row.type == .expense ? "支出" : "收入")
                    LabeledContent("分类", value: ledger.categoryName(row.categoryID))
                    LabeledContent("账户", value: ledger.accountName(row.accountID))
                    LabeledContent("业务日期", value: LedgerStyle.day(row.occurredAt.localEpochDay))
                    LabeledContent("时区", value: row.occurredAt.zoneID)
                    Text(LedgerStyle.occurred(row.occurredAt))
                    if let note = row.note { Text(note).textSelection(.enabled) }
                    if !row.tagIDs.isEmpty { Text(ledger.tags.filter { row.tagIDs.contains($0.id) }.map(\.name).joined(separator: "、")) }
                }
                Section("冻结估值") {
                    LabeledContent("本位币金额", value: row.convertedBase.plainText + " " + row.convertedBase.currencyCode.rawValue)
                    LabeledContent("汇率", value: row.exchangeRate.rate.text)
                    LabeledContent("来源", value: row.exchangeRate.providerID)
                }
                if managed {
                    Text("这笔损益随本金转账保存和撤销。请在设置 → 资金起点与本金转账中操作。")
                } else if checked {
                    if row.deletedAt != nil { Button("恢复账单") { Task { await ledger.restore(id: row.id); if ledger.error == nil { dismiss() } } } }
                    else {
                        Button("编辑账单") { editing = true }.accessibilityIdentifier("ledger.edit")
                        Button("删除账单", role: .destructive) { deleting = true }
                    }
                }
            }
            .navigationTitle("账单详情")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $editing, onDismiss: { dismiss() }) { EntryView(ledger: ledger, existing: row) }
            .confirmationDialog("删除后可撤销，也可从已删除账单恢复。", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除", role: .destructive) { Task { await ledger.delete(row); if ledger.error == nil { dismiss() } } }
            }
            .disabled(ledger.isBusy)
            .task {
                if let result = await ledger.managed(id: row.id) { managed = result; checked = true }
            }
        }
    }
}
