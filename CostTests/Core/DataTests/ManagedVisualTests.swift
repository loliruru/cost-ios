import Foundation
import CoreGraphics
import ImageIO
import GRDB
import Testing
@testable import Cost

struct ManagedVisualTests {
    func source(width: Int = 64, height: Int = 48) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let image = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "synthetic-private-metadata"]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
    @Test func encodesRealWebPStripsMetadataAndRespectsBothBounds() throws {
        let input = try source(width: 2200, height: 1300)
        for kind in [VisualAssetKind.icon, .background] {
            let result = try WebPImageProcessor.process(input, kind: kind)
            #expect(String(data: result.bytes.prefix(4), encoding: .ascii) == "RIFF")
            #expect(String(data: result.bytes[8..<12], encoding: .ascii) == "WEBP")
            #expect(result.width <= (kind == .icon ? 512 : 1920))
            #expect(result.height <= (kind == .icon ? 512 : 1080))
            let decoded = try #require(CGImageSourceCreateWithData(result.bytes as CFData, nil))
            #expect(CGImageSourceGetType(decoded) as String? == "org.webmproject.webp")
            let image = try #require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
            #expect(image.width == result.width && image.height == result.height)
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
            #expect(props[kCGImagePropertyExifDictionary] == nil && props[kCGImagePropertyGPSDictionary] == nil)
            #expect(CGImageSourceGetCount(decoded) == 1)
        }
        #expect(throws: (any Error).self) { try WebPImageProcessor.process(Data("invalid".utf8), kind: .icon) }
        #expect(throws: VisualAssetError.sourceTooLarge) { try WebPImageProcessor.process(Data(repeating: 0, count: VisualLimits.sourceBytes + 1), kind: .icon) }
    }
    @Test func leasesDedupReferencesMissingRepairAndCleanup() async throws {
        let database = try AppDatabase.inMemory()
        let repo = GRDBLedgerRepository(database: database)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cost-media-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.png"); try source().write(to: file)
        let store = ManagedVisualStore(database: database, root: root,
            environment: LedgerEnvironment(now: { 123456 }, newID: { "00000000-0000-0000-0000-000000000001" }))
        let first = try await store.importImage(file: file, kind: .icon, owner: "editor-one")
        let duplicate = try await store.importImage(file: file, kind: .icon, owner: "editor-two")
        #expect(first.id == "00000000-0000-0000-0000-000000000001" && first.createdAt == 123456)
        #expect(first.id == duplicate.id)
        try await store.cleanup()
        #expect(try await store.imageData(id: first.id) != nil)
        var account = try #require(try await repo.account(id: "seed-default-account"))
        account.visual = LedgerVisual(iconKey: "wallet", source: .image, iconAssetID: first.id)
        account.updatedAt = 100
        try await repo.saveAccount(account)
        await store.release(owner: "editor-one"); await store.release(owner: "editor-two")
        try await store.cleanup()
        #expect(try await store.imageData(id: first.id) != nil)
        account.isArchived = true; account.isDefault = false; account.updatedAt = 200
        try await repo.saveAccount(account); try await store.cleanup()
        #expect(try await store.imageData(id: first.id) != nil)
        let path = root.appendingPathComponent(first.relativePath)
        try FileManager.default.removeItem(at: path)
        #expect(try await store.imageData(id: first.id) == nil)
        #expect(try await store.importImage(file: file, kind: .icon, owner: "repair").id == first.id)
        #expect(try await store.imageData(id: first.id) != nil)
        try Data("corrupt".utf8).write(to: path)
        #expect(try await store.imageData(id: first.id) == nil)
        account.visual = LedgerVisual(iconKey: "wallet"); account.updatedAt = 300
        try await repo.saveAccount(account)
        await store.release(owner: "repair"); try await store.cleanup()
        #expect(try await store.imageData(id: first.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }
    @Test func failedMetadataSaveKeepsLeasedImageUntilEditorCloses() async throws {
        let database = try AppDatabase.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cost-media-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.png"); try source().write(to: file)
        let store = ManagedVisualStore(database: database, root: root)
        let asset = try await store.importImage(file: file, kind: .background, owner: "unsaved")
        let category = Category(id: "bad", name: "", type: .expense, visual: LedgerVisual(backgroundAssetID: asset.id), createdAt: 1, updatedAt: 1)
        await #expect(throws: (any Error).self) { try await GRDBLedgerRepository(database: database).saveCategory(category) }
        try await store.cleanup(); #expect(try await store.imageData(id: asset.id) != nil)
        await store.release(owner: "unsaved"); try await store.cleanup()
        #expect(try await store.imageData(id: asset.id) == nil)
    }
}
