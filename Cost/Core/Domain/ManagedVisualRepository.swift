import Foundation

protocol ManagedVisualRepository: Sendable {
    /// Imports a bounded private copy; owner leases protect unsaved editor references.
    func importImage(file: URL, kind: VisualAssetKind, owner: String) async throws -> VisualAsset
    func imageData(id: String) async throws -> Data?
    func release(owner: String) async
    func cleanup() async throws
}
