import SwiftUI

struct MetadataListView: View {
    @Bindable var ledger: LedgerViewModel
    let kind: MetadataKind
    @State private var route: MetadataRoute?
    var body: some View {
        List {
            if kind == .category {
                ForEach(ledger.categories, id: \.id) { row in
                    Button { route = MetadataRoute(recordID: row.id) } label: {
                        metadataRow(row.name, visual: row.visual, status: row.isArchived ? "已停用" : (row.type == .income ? "收入" : "支出"),
                            subcategory: row.parentID != nil)
                    }.foregroundStyle(.primary)
                }
            } else if kind == .account {
                ForEach(ledger.accounts, id: \.id) { row in
                    Button { route = MetadataRoute(recordID: row.id) } label: {
                        metadataRow(row.name, visual: row.visual, status: row.isArchived ? "已停用" : (row.isDefault ? "默认" : nil))
                    }.foregroundStyle(.primary)
                }
            } else {
                ForEach(ledger.tags, id: \.id) { row in
                    Button { route = MetadataRoute(recordID: row.id) } label: {
                        metadataRow(row.name, status: row.isArchived ? "已停用" : nil)
                    }.foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(kind.title)
        .costNavigationChrome()
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("新增\(kind.title)", systemImage: "plus") { route = MetadataRoute(recordID: nil) } } }
        .sheet(item: $route) { route in MetadataEditorView(ledger: ledger, kind: kind, recordID: route.recordID) }
        .refreshable { await ledger.reload() }
    }

    private func metadataRow(_ name: String, visual: LedgerVisual? = nil, status: String?, subcategory: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if let visual { LedgerIcon(visual: visual, repository: ledger.services.visuals) }
            VStack(alignment: .leading, spacing: 4) {
                if subcategory {
                    Label {
                        Text(name)
                    } icon: {
                        Image(systemName: "arrow.turn.down.right").accessibilityHidden(true)
                    }
                } else {
                    Text(name)
                }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel([name, subcategory ? "子分类" : nil, status].compactMap { $0 }.joined(separator: "，"))
    }
}

struct MetadataEditorView: View {
    @State private var model: MetadataViewModel
    @State private var confirmSave = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    init(ledger: LedgerViewModel, kind: MetadataKind, recordID: String?) {
        _model = State(initialValue: MetadataViewModel(ledger: ledger, kind: kind, recordID: recordID))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $model.name)
                    if model.kind != .tag {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("排序（小的在前）").font(.subheadline)
                            TextField("排序数字", text: $model.order)
                                .keyboardType(.numbersAndPunctuation)
                                .accessibilityIdentifier("metadata.sortOrder")
                        }
                    }
                    if model.kind == .category {
                        Picker("收支", selection: $model.type) { Text("支出").tag(TransactionType.expense); Text("收入").tag(TransactionType.income) }
                        Picker("父分类", selection: $model.parentID) {
                            Text("无（一级分类）").tag("")
                            ForEach(model.parents, id: \.id) { Text($0.name).tag($0.id) }
                        }
                    }
                    if model.kind == .account {
                        Picker("可选币种", selection: $model.currency) {
                            Text("不指定").tag("")
                            ForEach(model.ledger.currencies, id: \.code) { Text($0.code.rawValue).tag($0.code.rawValue) }
                        }
                        Toggle("默认账户", isOn: $model.isDefault).disabled(model.archived)
                        Text("账户币种不限制普通账单的原币种。").font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("停用", isOn: $model.archived)
                    if model.kind == .category { Text("停用父分类会同时停用子分类；恢复子项前请先恢复父分类。").font(.footnote).foregroundStyle(.secondary) }
                }
                if model.kind != .tag {
                    Section("图标") {
                        Picker("来源", selection: $model.visual.source) {
                            Text("内置图标").tag(IconSource.builtIn); Text("Emoji").tag(IconSource.emoji)
                            if model.visual.source == .image { Text("受管图片").tag(IconSource.image) }
                        }
                        if model.visual.source == .emoji {
                            TextField("单个 Emoji", text: Binding(get: { model.visual.emoji ?? "" }, set: { model.visual.emoji = $0 }))
                        } else {
                            Picker("内置图标", selection: $model.visual.iconKey) {
                                if !LedgerStyle.iconKeys.contains(model.visual.iconKey) {
                                    Label("当前图标", systemImage: LedgerStyle.symbol(model.visual.iconKey)).tag(model.visual.iconKey)
                                }
                                ForEach(LedgerStyle.iconKeys, id: \.self) { key in
                                    Label(LedgerStyle.iconTitle(key), systemImage: LedgerStyle.symbol(key)).tag(key)
                                }
                            }
                        }
                        LedgerIcon(visual: model.visual, repository: model.ledger.services.visuals)
                    }
                    VisualPickerControls(model: model)
                }
                if model.recordID != nil && model.archived && model.kind != .account {
                    Section {
                        Button("永久删除\(model.kind.title)", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text(model.kind == .tag ? "将移除该标签的账单、模板、循环关联，保留宿主记录和金额。" : "仅无子分类且无任何历史引用的已停用分类可以删除。")
                    }
                }
            }
            .navigationTitle((model.recordID == nil ? "新增" : "编辑") + model.kind.title)
            .costNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(model.isBusy) }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    if model.recordID != nil { confirmSave = true }
                    else { Task { if await model.save() { dismiss() } } }
                }.disabled(model.isBusy || model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .confirmationDialog("名称和视觉修改会影响历史显示，金额与冻结估值保持不变。", isPresented: $confirmSave, titleVisibility: .visible) {
                Button("保存修改") { Task { if await model.save() { dismiss() } } }
            }
            .confirmationDialog("确认永久删除？此操作不可撤销。", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("永久删除", role: .destructive) { Task { if await model.delete() { dismiss() } } }
            }
            .onChange(of: model.visual.source) { _, source in
                if source == .builtIn { model.visual.emoji = nil; model.visual.iconAssetID = nil }
                if source == .emoji { model.visual.iconAssetID = nil; if model.visual.emoji == nil { model.visual.emoji = "" } }
            }
            .interactiveDismissDisabled(model.isBusy)
            .onDisappear { Task { await model.close() } }
            .ledgerError($model.error)
        }
    }
}
