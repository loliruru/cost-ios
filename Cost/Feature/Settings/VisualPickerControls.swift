import SwiftUI
import PhotosUI

struct VisualPickerControls: View {
    @Bindable var model: MetadataViewModel
    @State private var iconSelection: PhotosPickerItem?
    @State private var backgroundSelection: PhotosPickerItem?
    var body: some View {
        Section("私有图片") {
            PhotosPicker("选择图片图标", selection: $iconSelection, matching: .images, preferredItemEncoding: .current)
            if let id = model.visual.iconAssetID {
                ManagedPicture(id: id, repository: model.ledger.services.visuals, icon: true).frame(width: 64, height: 64)
                Button("移除图片图标") { model.visual.source = .builtIn; model.visual.iconAssetID = nil }
            }
            PhotosPicker("选择背景图片", selection: $backgroundSelection, matching: .images, preferredItemEncoding: .current)
            if let id = model.visual.backgroundAssetID {
                ManagedPicture(id: id, repository: model.ledger.services.visuals, focus: model.visual.backgroundFocus).frame(height: 140).clipShape(.rect(cornerRadius: 12))
                Picker("背景焦点", selection: $model.visual.backgroundFocus) {
                    Text("顶部").tag(BackgroundFocus.top); Text("居中").tag(BackgroundFocus.center); Text("底部").tag(BackgroundFocus.bottom)
                }
                Button("移除背景") { model.visual.backgroundAssetID = nil }
            }
            if model.isBusy { ProgressView("正在处理图片") }
        }
        .disabled(model.isBusy)
        .onChange(of: iconSelection) { _, selection in Task { await load(selection, kind: .icon) } }
        .onChange(of: backgroundSelection) { _, selection in Task { await load(selection, kind: .background) } }
    }
    private func load(_ selection: PhotosPickerItem?, kind: VisualAssetKind) async {
        guard let selection, model.beginImageImport() else { return }
        do {
            guard let file = try await selection.loadTransferable(type: VisualImportFile.self) else { throw VisualAssetError.unsupportedImage }
            await model.importImage(file: file.url, kind: kind)
        } catch { model.imageImportFailed(error) }
    }
}
