import SwiftUI

struct QuickTemplatesView: View {
    @State private var model: QuickTemplatesViewModel
    @State private var editor: TemplateEditorRoute?
    @State private var entry: TemplateEntryRoute?

    init(ledger: LedgerViewModel) {
        _model = State(initialValue: QuickTemplatesViewModel(ledger: ledger))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                if let notice = model.notice {
                    Section {
                        Text(notice)
                        if model.recorded != nil {
                            Button("撤销记账") { Task { await model.undo() } }
                                .disabled(model.isBusy)
                                .accessibilityIdentifier("template.undo")
                        }
                    }
                }
                if model.rows.isEmpty {
                    ContentUnavailableView("暂无模板", systemImage: "square.on.square", description: Text("添加常用收支，下次可一键记账。"))
                } else {
                    templateSection("启用中", rows: model.rows.filter { !$0.isArchived })
                    templateSection("已停用", rows: model.rows.filter(\.isArchived))
                }
            }
            .navigationTitle("快捷模板")
            .costNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新增模板", systemImage: "plus") { editor = TemplateEditorRoute(template: nil) }
                        .accessibilityIdentifier("template.add")
                }
            }
            .task { await model.reload() }
            .refreshable { await model.ledger.reload(); await model.reload() }
            .sheet(item: $editor) { route in
                QuickTemplateEditorView(templates: model, existing: route.template)
            }
            .sheet(item: $entry) { route in
                EntryView(ledger: model.ledger, prefilled: route.draft).costEntrySheet()
            }
            .onChange(of: model.recorded?.id) { _, id in if id != nil { CostHaptics.success() } }
            .ledgerError($model.error)
        }
    }

    @ViewBuilder
    private func templateSection(_ title: String, rows: [QuickTemplate]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    QuickTemplateRow(template: row, disabled: model.isBusy,
                        editTemplate: { editor = TemplateEditorRoute(template: row) },
                        record: { Task { if let draft = await model.record(row) { entry = TemplateEntryRoute(draft: draft) } } },
                        editEntry: { Task { if let draft = await model.entryDraft(for: row) { entry = TemplateEntryRoute(draft: draft) } } })
                }
            }
        }
    }
}

private struct TemplateEditorRoute: Identifiable {
    let id = UUID()
    let template: QuickTemplate?
}

private struct TemplateEntryRoute: Identifiable {
    let draft: EntryDraft
    var id: String { draft.id }
}

private struct QuickTemplateRow: View {
    let template: QuickTemplate
    let disabled: Bool
    let editTemplate: () -> Void
    let record: () -> Void
    let editEntry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: editTemplate) {
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(template.content.name)
                    } icon: {
                        LedgerBuiltInIcon.image(for: template.content.iconKey)
                    }
                    .font(.headline)
                    Text("\(template.content.type == .expense ? "支出" : "收入") \(template.content.amount.plainText) \(template.content.amount.currencyCode.rawValue)")
                        .monospacedDigit()
                    Text("一键记账 \(template.usageCount) 次").font(.footnote).foregroundStyle(.secondary)
                    if let last = template.lastUsedAt {
                        let date = Date(timeIntervalSince1970: TimeInterval(last) / 1000)
                        Text("最近使用 \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityHint("打开模板设置")
            if !template.isArchived {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { actions }
                    VStack(alignment: .leading, spacing: 0) { actions }
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        Button(action: record) { Text("一键记账").frame(minHeight: 44) }
            .buttonStyle(.borderless)
            .disabled(disabled)
            .accessibilityLabel("一键记账，\(template.content.name)")
            .accessibilityIdentifier("template.record.\(template.id)")
        Button(action: editEntry) { Text("编辑后记账").frame(minHeight: 44) }
            .buttonStyle(.borderless)
            .disabled(disabled)
            .accessibilityLabel("编辑后记账，\(template.content.name)")
            .accessibilityIdentifier("template.editEntry.\(template.id)")
    }
}

private struct QuickTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: QuickTemplateEditorModel
    @State private var confirmingDelete = false

    init(templates: QuickTemplatesViewModel, existing: QuickTemplate?) {
        _model = State(initialValue: QuickTemplateEditorModel(templates: templates, existing: existing))
    }

    private var ledger: LedgerViewModel { model.templates.ledger }

    var body: some View {
        NavigationStack {
            Form {
                summaryFields
                ledgerFields
                noteAndTags
                if let existing = model.existing {
                    Section {
                        Button(existing.isArchived ? "恢复模板" : "停用模板") {
                            Task { if await model.setArchived() { dismiss() } }
                        }
                        Button("删除模板", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .disabled(model.isBusy)
            .navigationTitle(model.existing == nil ? "新增模板" : "编辑模板")
            .costNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(model.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { if await model.save() { dismiss() } } }
                        .disabled(model.isBusy || model.draft.name.isEmpty || model.draft.amount.isEmpty)
                        .accessibilityIdentifier("template.save")
                }
            }
            .confirmationDialog("删除此模板？已生成的账单会保留。", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除模板", role: .destructive) { Task { if await model.delete() { dismiss() } } }
            }
            .interactiveDismissDisabled(model.isBusy)
            .onChange(of: model.draft.type) { _, type in model.selectCategory(for: type) }
            .ledgerError($model.error)
        }
    }

    private var summaryFields: some View {
        Section {
            TextField("名称", text: $model.draft.name).accessibilityIdentifier("template.name")
            LedgerBuiltInIconPicker(title: "图标", selection: $model.draft.iconKey)
            VStack(alignment: .leading, spacing: 6) {
                Text("排序（小的在前）").font(.subheadline)
                TextField("自动排序", text: $model.order).keyboardType(.numbersAndPunctuation)
            }
        }
    }

    private var ledgerFields: some View {
        Section("记账内容") {
            Picker("收支", selection: $model.draft.type) {
                Text("支出").tag(TransactionType.expense)
                Text("收入").tag(TransactionType.income)
            }
            TextField("金额", text: $model.draft.amount).keyboardType(.decimalPad)
                .accessibilityIdentifier("template.amount")
            Picker("币种", selection: $model.draft.currencyCode) {
                if !ledger.currencies.contains(where: { $0.code.rawValue == model.draft.currencyCode }) {
                    Text(model.draft.currencyCode).tag(model.draft.currencyCode)
                }
                ForEach(ledger.currencies.filter { $0.assetType == .fiat }, id: \.code) { currency in
                    Text(currency.code.rawValue).tag(currency.code.rawValue)
                }
            }
            Picker("分类", selection: $model.draft.categoryID) {
                Text("请选择").tag("")
                ForEach(ledger.categories.filter { $0.type == model.draft.type && (!$0.isArchived || $0.id == model.existing?.content.categoryID) }, id: \.id) {
                    Text($0.name + ($0.isArchived ? "（已停用）" : "")).tag($0.id)
                }
            }
            Picker("账户", selection: $model.draft.accountID) {
                Text("请选择").tag("")
                ForEach(ledger.accounts.filter { !$0.isArchived || $0.id == model.existing?.content.accountID }, id: \.id) {
                    Text($0.name + ($0.isArchived ? "（已停用）" : "")).tag($0.id)
                }
            }
        }
    }

    private var noteAndTags: some View {
        Section {
            TextField("备注", text: $model.draft.note, axis: .vertical).lineLimit(3...8)
            ForEach(ledger.tags.filter { !$0.isArchived || model.draft.tagIDs.contains($0.id) }, id: \.id) { tag in
                Toggle(tag.name, isOn: Binding(get: { model.draft.tagIDs.contains(tag.id) }, set: { selected in
                    if selected { model.draft.tagIDs.insert(tag.id) }
                    else { model.draft.tagIDs.remove(tag.id) }
                }))
            }
        }
    }
}
