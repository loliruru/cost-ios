import SwiftUI
import Observation
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

/// System picker adapter. It bounds the provider file before copying, without loading an original into UI memory.
struct VisualImportFile: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let handle = try FileHandle(forReadingFrom: received.file)
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: VisualLimits.sourceBytes + 1) ?? Data()
            guard !bytes.isEmpty, bytes.count <= VisualLimits.sourceBytes else { throw VisualAssetError.sourceTooLarge }
            let target = FileManager.default.temporaryDirectory.appendingPathComponent("cost-import-\(UUID().uuidString)")
            try bytes.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return Self(url: target)
        }
    }
}

@MainActor @Observable
final class VisualMediaViewModel {
    var bytes: Data?
    func load(id: String?, repository: any ManagedVisualRepository) async {
        bytes = nil
        guard let id else { return }
        let data = try? await repository.imageData(id: id)
        guard !Task.isCancelled else { return }
        bytes = data
    }
}

struct ManagedPicture: View {
    let id: String?
    let repository: any ManagedVisualRepository
    var focus = BackgroundFocus.center
    var icon = false
    @State private var model = VisualMediaViewModel()
    private var alignment: Alignment { focus == .top ? .top : (focus == .bottom ? .bottom : .center) }
    var body: some View {
        GeometryReader { geometry in
            if let data = model.bytes, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment).clipped()
            } else {
                Image(systemName: icon ? "photo" : "photo.badge.exclamationmark").frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.secondary)
            }
        }
        .task(id: id) { await model.load(id: id, repository: repository) }
        .accessibilityHidden(true)
    }
}

