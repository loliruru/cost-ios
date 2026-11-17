import Foundation

enum VisualAssetKind: String, Sendable { case icon = "ICON", background = "BACKGROUND" }
enum VisualAssetError: Error, Equatable, Sendable { case sourceTooLarge, dimensionsTooLarge, unsupportedImage, decodeFailed, storageFailure }
enum VisualLimits {
    static let sourceBytes = 16 * 1024 * 1024
    static let outputBytes = 8 * 1024 * 1024
}
struct VisualAsset: Equatable, Sendable {
    let id: String
    let kind: VisualAssetKind
    let relativePath: String
    let width: Int
    let height: Int
    let byteSize: Int
    let sha256: String
    let createdAt: Int64
}
