import SwiftUI

struct FundsRoute: Identifiable { let id = UUID(); var account: Account?; var transfer: AccountTransfer? }
struct FundsListView: View {
    @Bindable var ledger: LedgerViewModel
    @State private var route: FundsRoute?
    var body: some View {
        List {
            Section("当前资金（点击设置或校准）") {
                ForEach(ledger.accounts, id: \.id) { account in
                    let position = ledger.positions.first { $0.accountID == account.id }
                    Button { route = FundsRoute(account: account) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(account.name + (account.isArchived ? "（已停用）" : ""))
                            if let amount = position?.amount {
                                Text((position?.opening?.kind == .investmentCost ? "投入成本 " : "可用金额 ") + amount.text + " " + (position?.opening?.currencyCode.rawValue ?? "")).monospacedDigit()
                                if let missing = position?.unvaluedCount, missing > 0 { Text("\(missing) 项待核对，金额不完整").foregroundStyle(.orange) }
                            } else { Text("未设置金额").foregroundStyle(.secondary) }
                        }.fixedSize(horizontal: false, vertical: true)
                    }.foregroundStyle(.primary).disabled(account.isArchived)
                }
            }
            Section("最近本金转账（最多 200 笔，含已撤销）") {
                ForEach(ledger.transfers, id: \.id) { transfer in
                    Button { route = FundsRoute(transfer: transfer) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ledger.accountName(transfer.fromAccountID) + " → " + ledger.accountName(transfer.toAccountID))
                            Text("本金 " + FundAmount(units: transfer.principalMinor, scale: transfer.scale).text + " " + transfer.currencyCode.rawValue).monospacedDigit()
                            if transfer.profitMinor != 0 { Text("损益 " + FundAmount(units: transfer.profitMinor, scale: transfer.scale).text).monospacedDigit() }
                            if transfer.deletedAt != nil { Text("已撤销").foregroundStyle(.secondary) }
                        }
                    }.foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("账户资金")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("本金转账", systemImage: "plus") { route = FundsRoute() } } }
        .sheet(item: $route) { route in FundsEditorView(ledger: ledger, account: route.account, existing: route.transfer) }
        .refreshable { await ledger.reload() }
    }
}

struct FundsEditorView: View {
    @State private var model: FundsViewModel
    @State private var confirm = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    init(ledger: LedgerViewModel, account: Account?, existing: AccountTransfer?) {
        _model = State(initialValue: FundsViewModel(ledger: ledger, account: account, existing: existing))
    }
    var body: some View {
        NavigationStack {
            Form {
                if let account = model.account {
                    Section {
                        Toggle("追踪资金", isOn: $model.enabled)
                        Picker("计算方式", selection: $model.kind) {
                            Text("可用金额").tag(AccountAmountKind.available); Text("投入成本").tag(AccountAmountKind.investmentCost)
                        }
                        currencyPicker
                        if model.enabled { TextField("新的当前金额（允许零）", text: $model.amount).keyboardType(.decimalPad) }
                    } header: { Text(account.name) } footer: { Text("每次保存追加一个起点。旧账不追扣；关闭后再开启需重新输入当前金额。投入成本只计本金，不随普通收支或市场价格变化。") }
                } else {
                    Section {
                        accountPicker("转出", selection: $model.from)
                        accountPicker("转入", selection: $model.to)
                        currencyPicker
                        TextField("本金（允许零）", text: $model.principal).keyboardType(.decimalPad)
                        TextField("损益（亏损带负号）", text: $model.profit).keyboardType(.numbersAndPunctuation)
                        Picker("损益分类", selection: $model.categoryID) {
                            Text("无").tag("")
                            ForEach(model.ledger.categories.filter { !$0.isArchived }, id: \.id) { Text(($0.type == .income ? "收入 · " : "支出 · ") + $0.name).tag($0.id) }
                        }
                    } header: { Text("本金") } footer: { Text("只支持同币法币本金转账。损益仅适用于投入成本 → 可用金额，自动关联收支账单。手续费请单独记支出。") }
                    Section {
                        DatePicker("发生时间", selection: $model.date).environment(\.timeZone, TimeZone(identifier: model.zoneID) ?? .current)
                        LabeledContent("时区", value: model.zoneID)
                        TextField("备注", text: $model.note, axis: .vertical)
                    }
                    if let existing = model.existing {
                        Section {
                            Button(existing.deletedAt == nil ? "撤销整笔转账" : "恢复整笔转账", role: existing.deletedAt == nil ? .destructive : nil) { confirmDelete = true }
                        } footer: { Text("本金和关联损益会在同一事务内撤销或恢复。资金不足等冲突会拒绝整次操作。") }
                    }
                }
            }
            .navigationTitle(model.account == nil ? "本金转账" : "资金起点")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    if model.account != nil { confirm = true }
                    else { Task { if await model.save() { dismiss() } } }
                }.disabled(model.isBusy || model.existing?.deletedAt != nil) }
            }
            .confirmationDialog("以保存时刻为新起点，之前的账单不会追扣。确认保存？", isPresented: $confirm, titleVisibility: .visible) {
                Button("保存新起点") { Task { if await model.save() { dismiss() } } }
            }
            .confirmationDialog("确认对本金与关联损益一并操作？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(model.existing?.deletedAt == nil ? "撤销" : "恢复") { Task { if await model.setDeleted(model.existing?.deletedAt == nil) { dismiss() } } }
            }
            .interactiveDismissDisabled(model.isBusy)
            .ledgerError($model.error)
        }
    }
    private var currencyPicker: some View {
        Picker("法币", selection: $model.code) {
            ForEach(model.ledger.currencies.filter { $0.assetType == .fiat }, id: \.code) { Text($0.code.rawValue).tag($0.code.rawValue) }
        }
    }
    private func accountPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("请选择").tag("")
            ForEach(model.ledger.accounts.filter { !$0.isArchived }, id: \.id) { Text($0.name).tag($0.id) }
        }
    }
}
