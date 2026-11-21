import SwiftUI

struct EntryView: View {
    let ledger: LedgerViewModel
    @State private var model: EntryViewModel
    @State private var more = false
    @State private var newTag = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(ledger: LedgerViewModel, existing: LedgerTransaction? = nil, prefilled: EntryDraft? = nil) {
        self.ledger = ledger
        _model = State(initialValue: EntryViewModel(services: ledger.services, categories: ledger.categories,
            accounts: ledger.accounts, environment: ledger.environment, baseCurrency: ledger.baseCurrency, existing: existing, prefilled: prefilled))
        _more = State(initialValue: prefilled.map { $0.currencyCode != $0.baseCurrencyCode }
            ?? existing.map { $0.original.currencyCode != $0.convertedBase.currencyCode } ?? false)
    }
    private var date: Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: TimeInterval(model.draft.occurredMillis) / 1000) },
            set: { model.draft.occurredMillis = Int64($0.timeIntervalSince1970 * 1000) })
    }
    private var crypto: Bool {
        ledger.currencies.first { $0.code.rawValue == model.draft.currencyCode }?.assetType == .crypto ||
            (model.draft.currencyCode == model.existing?.original.currencyCode.rawValue && model.existing?.crypto != nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                if model.restored { Text("已恢复上次草稿").foregroundStyle(.secondary) }
                Section {
                    Picker("收支", selection: $model.draft.type) {
                        Text("支出").tag(TransactionType.expense); Text("收入").tag(TransactionType.income)
                    }.pickerStyle(.segmented)
                    TextField("金额", text: $model.draft.amount).keyboardType(.decimalPad).font(.largeTitle).monospacedDigit()
                        .accessibilityLabel("金额，\(model.draft.currencyCode)").accessibilityIdentifier("entry.amount")
                    Picker("币种", selection: Binding(get: { model.draft.currencyCode }, set: { model.selectCurrency($0) })) {
                        let available = ledger.currencies.filter { model.draft.sourceTemplateID == nil || $0.assetType == .fiat }
                        if !available.contains(where: { $0.code.rawValue == model.draft.currencyCode }) {
                            Text(model.draft.currencyCode).tag(model.draft.currencyCode)
                        }
                        ForEach(available, id: \.code) { Text($0.code.rawValue + " · " + $0.displayName).tag($0.code.rawValue) }
                    }.accessibilityIdentifier("entry.currency")
                    Picker("分类", selection: $model.draft.categoryID) {
                        Text("请选择").tag("")
                        ForEach(ledger.categories.filter { $0.type == model.draft.type && (!$0.isArchived || $0.id == model.existing?.categoryID) }, id: \.id) { category in
                            Text((category.parentID == nil ? "" : "　↳ ") + category.name + (category.isArchived ? "（已停用）" : "")).tag(category.id)
                        }
                    }.accessibilityIdentifier("entry.category")
                } footer: { Text("先填写金额和分类，即可保存。关闭会保留草稿。") }
                DisclosureGroup("账户、日期、备注与标签", isExpanded: $more) {
                    Picker("账户", selection: $model.draft.accountID) {
                        Text("请选择").tag("")
                        ForEach(ledger.accounts.filter { !$0.isArchived || $0.id == model.existing?.accountID }, id: \.id) { Text($0.name + ($0.isArchived ? "（已停用）" : "")).tag($0.id) }
                    }
                    DatePicker("发生时间", selection: date).environment(\.timeZone, TimeZone(identifier: model.draft.zoneID) ?? .current)
                    LabeledContent("冻结时区", value: model.draft.zoneID)
                    TextField("备注", text: $model.draft.note, axis: .vertical).lineLimit(3...8)
                    ForEach(ledger.tags.filter { !$0.isArchived || model.draft.tagIDs.contains($0.id) }, id: \.id) { tag in
                        Toggle(tag.name, isOn: Binding(get: { model.draft.tagIDs.contains(tag.id) }, set: { if $0 { model.draft.tagIDs.insert(tag.id) } else { model.draft.tagIDs.remove(tag.id) } }))
                    }
                    HStack {
                        TextField("新标签（同名自动复用）", text: $newTag)
                        Button("添加") { Task {
                            if await model.addTag(name: newTag) { newTag = ""; await ledger.reload() }
                        } }.disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ledger.isBusy)
                    }
                }
                if model.draft.currencyCode != model.draft.baseCurrencyCode { valuationSection }
            }
            .disabled(model.isBusy)
            .navigationTitle(model.existing != nil ? "编辑账单" : (model.draft.sourceTemplateID == nil ? "记一笔" : "从模板记账"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { Task { await model.persist(); dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isBusy ? "保存中" : "保存") { Task { if await model.save() { await ledger.reload(); dismiss() } } }
                        .disabled(model.isBusy || model.draft.amount.isEmpty || model.draft.categoryID.isEmpty || model.draft.accountID.isEmpty)
                        .accessibilityIdentifier("entry.save")
                }
            }
            .interactiveDismissDisabled(model.isBusy)
            .task { await model.load() }
            .onChange(of: model.draft) { _, _ in Task { await model.persist() } }
            .onChange(of: model.quoteBasis) { _, _ in model.clearOffer() }
            .onChange(of: model.draft.type) { _, type in
                if !ledger.categories.contains(where: { $0.id == model.draft.categoryID && $0.type == type }) {
                    model.draft.categoryID = ledger.categories.first { $0.type == type && !$0.isArchived }?.id ?? ""
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await model.persist() } } }
            .onDisappear { Task { await model.persist() } }
            .ledgerError($model.error)
        }
    }

    private var valuationSection: some View {
        Section("本位币估值 · \(model.draft.baseCurrencyCode)") {
            if let existing = model.existing, existing.original.currencyCode.rawValue == model.draft.currencyCode {
                LabeledContent("已冻结金额", value: existing.convertedBase.plainText + " " + existing.convertedBase.currencyCode.rawValue)
            }
            TextField("实际结算金额", text: Binding(get: { model.draft.actualBaseAmount ?? "" }, set: { model.draft.actualBaseAmount = $0 }))
                .keyboardType(.decimalPad).accessibilityIdentifier("entry.actualSettlement")
            TextField(crypto ? "实际单价（每单位）" : "手工汇率（每单位原币）",
                text: Binding(get: { model.draft.manualRate ?? "" }, set: { model.draft.manualRate = $0 }))
                .keyboardType(.decimalPad).accessibilityIdentifier("entry.manualRate")
            Button(model.offer == nil ? (crypto ? "获取市场参考价" : "查询汇率") : "重新查询报价") {
                Task { await model.fetchOffer() }
            }.accessibilityIdentifier("entry.fetchQuote")
            if let offer = model.offer {
                FrozenQuoteRows(snapshot: offer.snapshot, venue: offer.venue)
                if offer.requiresConfirmation {
                    Toggle(offer.snapshot.method == .currentFallback ? "确认使用当前汇率" : "确认使用过期报价", isOn: $model.acceptsFallback)
                        .accessibilityIdentifier("entry.confirmQuote")
                }
            }
        } footer: {
            Text(crypto ? "市场参考价需主动获取。过去的账单请填写实际单价或结算金额。"
                : "实际结算金额优先于手工汇率。未填写时，保存会查询对应业务日。最新报价按数据时间计算，超过 5 分钟标为过期。")
        }
    }
}
