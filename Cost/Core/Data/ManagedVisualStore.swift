import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import GRDB
import libwebp

struct ProcessedVisual: Sendable {
    let bytes: Data
    let width: Int
    let height: Int
}

enum WebPImageProcessor {
    static func process(_ bytes: Data, kind: VisualAssetKind) throws -> ProcessedVisual {
        guard !bytes.isEmpty, bytes.count <= VisualLimits.sourceBytes else { throw VisualAssetError.sourceTooLarge }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              ["public.png", "public.jpeg", "public.heic", "public.heif", "org.webmproject.webp", "com.compuserve.gif"].contains(type),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { throw VisualAssetError.unsupportedImage }
        guard width <= 16384, height <= 16384, width * height <= 40_000_000 else { throw VisualAssetError.dimensionsTooLarge }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let orientedWidth = (5...8).contains(orientation) ? height : width
        let orientedHeight = (5...8).contains(orientation) ? width : height
        let edge = max(width, height)
        let bound = kind == .icon ? 512 : min(1920 * edge / orientedWidth, 1080 * edge / orientedHeight)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: min(edge, bound),
            kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw VisualAssetError.decodeFailed }
        let output = try encode(image)
        guard output.count <= VisualLimits.outputBytes else { throw VisualAssetError.sourceTooLarge }
        return ProcessedVisual(bytes: output, width: image.width, height: image.height)
    }

    /// Raw sRGB pixels remove all EXIF/GPS/XMP and animation. Unpremultiply before libwebp.
    static func encode(_ image: CGImage) throws -> Data {
        let width = image.width, height = image.height, stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        return try pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { throw VisualAssetError.decodeFailed }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            let pointer = raw.bindMemory(to: UInt8.self)
            for index in Swift.stride(from: 0, to: pointer.count, by: 4) {
                let alpha = Int(pointer[index + 3])
                for channel in 0..<3 {
                    pointer[index + channel] = alpha == 0 ? 0 : UInt8(min(255, (Int(pointer[index + channel]) * 255 + alpha / 2) / alpha))
                }
            }
            var result: UnsafeMutablePointer<UInt8>?
            let count = WebPEncodeLosslessRGBA(pointer.baseAddress, Int32(width), Int32(height), Int32(stride), &result)
            guard count > 0, let result else { throw VisualAssetError.decodeFailed }
            defer { WebPFree(result) }
            return Data(bytes: result, count: count)
        }
    }
}

actor ManagedVisualStore: ManagedVisualRepository {
    let database: AppDatabase
    let root: URL
    let environment: LedgerEnvironment
    private var leases: [String: Set<String>] = [:]
    private var maintenanceBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private func acquire() async {
        if maintenanceBusy { await withCheckedContinuation { waiters.append($0) } }
        else { maintenanceBusy = true }
    }
    private func unlock() {
        if waiters.isEmpty { maintenanceBusy = false }
        else { waiters.removeFirst().resume() }
    }
    func withMaintenance<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { unlock() }
        try Task.checkCancellation()
        return try await work()
    }
    init(database: AppDatabase, root: URL, environment: LedgerEnvironment = LedgerEnvironment()) {
        self.database = database; self.root = root; self.environment = environment
    }
    static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Cost", isDirectory: true)
    }
    func importImage(file: URL, kind: VisualAssetKind, owner: String) async throws -> VisualAsset {
        await acquire(); defer { unlock() }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let input = try handle.read(upToCount: VisualLimits.sourceBytes + 1) ?? Data()
        let processed = try WebPImageProcessor.process(input, kind: kind)
        let hash = SHA256.hash(data: processed.bytes).map { String(format: "%02x", $0) }.joined()
        if let duplicate = try await database.writer.read({ db in
            try VisualAssetRecord.fetchOne(db, sql: "SELECT * FROM visual_assets WHERE asset_kind = ? AND content_sha256 = ? AND processing_version = 1", arguments: [kind.rawValue, hash])
        }) {
            leases[owner, default: []].insert(duplicate.id)
            // Repair a missing/corrupted derived copy with the same validated bytes.
            let url = try resolve(duplicate.relative_path)
            try publish(processed.bytes, to: url)
            return try duplicate.visualModel()
        }
        let id = environment.newID().lowercased()
        let path = "visual_assets/\(id).webp"
        let url = try resolve(path)
        leases[owner, default: []].insert(id)
        do {
            try publish(processed.bytes, to: url)
            let row = VisualAssetRecord(id: id, asset_kind: kind.rawValue, relative_path: path, mime_type: "image/webp",
                width_px: Int64(processed.width), height_px: Int64(processed.height), byte_size: Int64(processed.bytes.count),
                content_sha256: hash, processing_version: 1, created_at_epoch_millis: environment.now())
            try await database.writer.write { db in try row.insert(db) }
            return try row.visualModel()
        } catch {
            leases[owner]?.remove(id); try? FileManager.default.removeItem(at: url)
            throw VisualAssetError.storageFailure
        }
    }
    private func resolve(_ path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "visual_assets", parts[1].hasSuffix(".webp"),
              UUID(uuidString: String(parts[1].dropLast(5))) != nil else { throw VisualAssetError.storageFailure }
        let url = root.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: url.path), try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw VisualAssetError.storageFailure }
        return url
    }
    private func publish(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }
    func imageData(id: String) async throws -> Data? {
        guard let record = try await database.writer.read({ db in try VisualAssetRecord.fetchOne(db, key: id) }) else { return nil }
        let model = try record.visualModel()
        let url = try resolve(model.relativePath)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: VisualLimits.outputBytes + 1) ?? Data()
        guard data.count == model.byteSize, data.count <= VisualLimits.outputBytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == model.sha256 else { return nil }
        return data
    }
    func release(owner: String) async {
        await acquire(); defer { unlock() }
        leases.removeValue(forKey: owner)
    }
    func cleanup() async throws {
        await acquire(); defer { unlock() }
        let protected = leases.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        let removed = try await database.writer.write { db in
            let rows = try VisualAssetRecord.fetchAll(db)
            var removed: [VisualAssetRecord] = []
            for row in rows where !protected.contains(row.id) {
                let referenced = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM categories WHERE icon_asset_id = ? OR background_asset_id = ? UNION ALL SELECT 1 FROM accounts WHERE icon_asset_id = ? OR background_asset_id = ?)", arguments: [row.id, row.id, row.id, row.id]) ?? true
                if !referenced { _ = try row.delete(db); removed.append(row) }
            }
            return removed
        }
        for row in removed { try? FileManager.default.removeItem(at: resolve(row.relative_path)) }
        // An interrupted publish may leave a file without a row. All in-flight files have leases.
        let known = try await database.writer.read { db in Set(try VisualAssetRecord.fetchAll(db).map(\.relative_path)) }
        let directory = root.appendingPathComponent("visual_assets", isDirectory: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? [] {
            let path = "visual_assets/\(file.lastPathComponent)"
            if !known.contains(path), !protected.contains(String(file.lastPathComponent.dropLast(5))),
               (try? resolve(path)) != nil { try? FileManager.default.removeItem(at: file) }
        }
    }
}

extension VisualAssetRecord {
    func visualModel() throws -> VisualAsset {
        guard let kind = VisualAssetKind(rawValue: asset_kind), mime_type == "image/webp", processing_version == 1,
              width_px > 0, height_px > 0, width_px <= 1920, height_px <= 1920,
              byte_size > 0, byte_size <= VisualLimits.outputBytes,
              content_sha256.count == 64, content_sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw VisualAssetError.storageFailure }
        guard kind == .icon ? max(width_px, height_px) <= 512 : (width_px <= 1920 && height_px <= 1080) else { throw VisualAssetError.storageFailure }
        return VisualAsset(id: id, kind: kind, relativePath: relative_path, width: Int(width_px), height: Int(height_px),
            byteSize: Int(byte_size), sha256: content_sha256, createdAt: created_at_epoch_millis)
    }
}
