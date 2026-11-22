import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct PortableDataView: View {
    @Bindable var model: PortableDataViewModel
    @State private var password = ""
    @State private var importKind = PortableDataKind.csv
    @State private var showingImporter = false
    @State private var showingConfirmation = false
    @State private var exportDocument: ExportDocument?

    var body: some View {
        Form {
            Section {
                Button("导出账单 CSV", systemImage: "square.and.arrow.up") { startExport(.csv) }
                    .accessibilityIdentifier("portable.export.csv")
                Button("导入 Cost CSV", systemImage: "square.and.arrow.down") { startImport(.csv) }
                    .accessibilityIdentifier("portable.import.csv")
            } header: {
                Text("账单 CSV")
            } footer: {
                Text("包含账单和引用资料。账户资金、图片、模板和周期规则需用完整备份。")
            }
            Section {
                SecureField("备份密码（可选）", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("portable.password")
                Button("导出完整备份", systemImage: "archivebox") { startExport(.backup) }
                    .accessibilityIdentifier("portable.export.backup")
                Button("从备份恢复", systemImage: "arrow.counterclockwise") { startImport(.backup) }
                    .accessibilityIdentifier("portable.import.backup")
            } header: {
                Text("完整备份")
            } footer: {
                Text("填写密码可加密新备份。恢复加密备份时需输入原密码。恢复会替换此设备的账本和备份设置。")
            }
            if model.busy { ProgressView("正在处理文件…") }
            if let status = model.status { Text(status).accessibilityIdentifier("portable.status") }
        }
        .disabled(model.busy)
        .navigationTitle("导入与备份")
        .costNavigationChrome()
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: importKind == .csv ? [.commaSeparatedText] : [.data]) { result in
            let kind = importKind
            let secret = takePassword(for: kind)
            switch result {
            case .success(let url):
                Task { showingConfirmation = await model.prepare(url, kind: kind, password: secret) }
            case .failure(let failure):
                if (failure as NSError).code != NSUserCancelledError { model.error = "无法打开所选文件。" }
            }
        }
        .sheet(item: $exportDocument) { document in
            PortableExportPicker(file: document.url) { saved in
                exportDocument = nil
                Task { await model.finishExport(document.url, saved: saved) }
            }
            .interactiveDismissDisabled()
        }
        .alert(model.preview?.kind == .backup ? "替换当前账本？" : "导入账单？", isPresented: $showingConfirmation) {
            if model.preview?.kind == .backup {
                Button("替换账本", role: .destructive) { Task { await model.apply() } }
            } else {
                Button("导入") { Task { await model.apply() } }
            }
            Button("取消", role: .cancel) { Task { await model.discard() } }
        } message: {
            if let preview = model.preview {
                if preview.kind == .backup {
                    Text("备份含 \(preview.transactions) 笔账单和 \(preview.images) 张图片。当前账本和备份设置将被替换。")
                } else {
                    Text("文件含 \(preview.transactions) 笔账单。相同账单将跳过，出现冲突时整次导入取消。")
                }
            }
        }
        .alert("操作失败", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好", role: .cancel) { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private struct ExportDocument: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private func takePassword(for kind: PortableDataKind) -> String {
        guard kind == .backup else { return "" }
        defer { password = "" }
        return password
    }

    private func startImport(_ kind: PortableDataKind) {
        importKind = kind
        showingImporter = true
    }

    private func startExport(_ kind: PortableDataKind) {
        let secret = takePassword(for: kind)
        Task {
            if let file = await model.export(kind, password: secret) { exportDocument = ExportDocument(url: file) }
        }
    }
}

private struct PortableExportPicker: UIViewControllerRepresentable {
    let file: URL
    let finish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finish: (Bool) -> Void
        init(finish: @escaping (Bool) -> Void) { self.finish = finish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(!urls.isEmpty) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(false) }
    }
}
