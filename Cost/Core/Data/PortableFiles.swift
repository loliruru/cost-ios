import CryptoKit
import Foundation

enum PortableLimits {
    static let archive = 256 * 1024 * 1024
    static let database = 128 * 1024 * 1024
    static let settings = 8192
    static let manifest = 2 * 1024 * 1024
    static let csv = 32 * 1024 * 1024
    static let csvRows = 100_000
    static let csvCellUTF16 = 256 * 1024
    static let entries = 4096

    static func assetPath(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "visual_assets", parts[1].hasSuffix(".webp") else { return false }
        let stem = parts[1].dropLast(5).utf8
        return (1...100).contains(stem.count) && stem.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    static func entry(_ name: String) throws -> Int {
        switch name {
        case "database.sqlite": return database
        case "settings.json": return settings
        case "manifest.json": return manifest
        default:
            guard assetPath(name) else { throw PortableDataError.invalidFormat }
            return VisualLimits.outputBytes
        }
    }
}

enum PortableFiles {
    static let chunkSize = 64 * 1024

    static func removeIfPresent(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }

    static func directory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }

    static func openOutput(_ url: URL) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
            throw PortableDataError.storage
        }
        return try FileHandle(forWritingTo: url)
    }

    static func read(_ input: FileHandle, count: Int) throws -> Data {
        if count == 0 { return Data() }
        guard let data = try input.read(upToCount: count), data.count == count else {
            throw PortableDataError.invalidFormat
        }
        return data
    }

    static func size(_ file: URL, limit: Int) throws -> Int {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else {
            throw PortableDataError.invalidFormat
        }
        guard size <= limit else { throw PortableDataError.tooLarge }
        return size
    }

    @discardableResult
    static func chunks(_ file: URL, limit: Int, _ consume: (Data) throws -> Void) throws -> Int {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var size = 0
        while let block = try input.read(upToCount: chunkSize), !block.isEmpty {
            try Task.checkCancellation()
            size += block.count
            guard size <= limit else { throw PortableDataError.tooLarge }
            try consume(block)
        }
        return size
    }

    static func copy(_ source: URL, to destination: URL, limit: Int) throws {
        try directory(destination.deletingLastPathComponent())
        let output = try openOutput(destination)
        defer { try? output.close() }
        try chunks(source, limit: limit) { try output.write(contentsOf: $0) }
        try output.synchronize()
    }

    static func digest(_ file: URL, limit: Int) throws -> PortableFileDigest {
        var hash = SHA256()
        let size = try chunks(file, limit: limit) { hash.update(data: $0) }
        return PortableFileDigest(size: size, sha256: hex(hash.finalize()))
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

struct PortableFileDigest: Codable, Equatable, Sendable {
    let size: Int
    let sha256: String
}
