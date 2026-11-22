import CoreGraphics
import Foundation
import GRDB
import ImageIO

struct PortableManifest: Codable {
    let format: Int
    let schema: Int
    let files: [String: PortableFileDigest]
    let visual_assets: [PortableRecord]
}

enum PortableBackup {
    static func export(_ target: URL, in directory: URL, snapshot: DatabaseQueue, mediaRoot: URL,
                       settings: PortableSettings, password: String) throws {
        let root = directory.appendingPathComponent("payload", isDirectory: true)
        try PortableFiles.directory(root)
        let databaseURL = root.appendingPathComponent("database.sqlite")
        let settingsURL = root.appendingPathComponent("settings.json")
        let manifestURL = root.appendingPathComponent("manifest.json")
        let exchange = try AndroidExchangeSchema.load().makeDatabase(at: databaseURL)
        let manifest = try snapshot.read { source in
            try exchange.write { database in
                for table in PortableLedger.tables { try PortableLedger.copy(table, from: source, to: database) }
                try PortableLedger.checkReferences(database)
            }
            try validateBaseCurrency(settings, in: source)
            try settings.encoded().write(to: settingsURL, options: .completeFileProtectionUntilFirstUserAuthentication)
            var entries = [
                "database.sqlite": try PortableFiles.digest(databaseURL, limit: PortableLimits.database),
                "settings.json": try PortableFiles.digest(settingsURL, limit: PortableLimits.settings),
            ]
            var assets: [PortableRecord] = []
            var total = entries.values.reduce(0) { $0 + $1.size }
            try PortableLedger.rows("visual_assets", in: source) { row in
                let model = try VisualAssetRecord(row: row).visualModel()
                guard PortableLimits.assetPath(model.relativePath), assets.count < PortableLimits.entries - 3 else {
                    throw PortableDataError.tooLarge
                }
                let origin = mediaRoot.appendingPathComponent(model.relativePath)
                try validateImage(model, at: origin)
                total += model.byteSize
                guard total <= PortableLimits.archive else { throw PortableDataError.tooLarge }
                let destination = root.appendingPathComponent(model.relativePath)
                try PortableFiles.copy(origin, to: destination, limit: model.byteSize)
                entries[model.relativePath] = PortableFileDigest(size: model.byteSize, sha256: model.sha256)
                assets.append(try PortableLedger.record(row))
            }
            return PortableManifest(format: 1, schema: AndroidExchangeSchema.current, files: entries, visual_assets: assets)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .completeFileProtectionUntilFirstUserAuthentication)
        let zip = directory.appendingPathComponent("payload.zip")
        try PortableZIP.write(zip, root: root, names: manifest.files.keys.sorted() + ["manifest.json"])
        try BackupEnvelope.encode(zip, to: target, password: password)
    }

    static func stage(_ file: URL, in directory: URL, database: DatabaseQueue, password: String) throws -> PortableSettings {
        let zip = directory.appendingPathComponent("payload.zip")
        try BackupEnvelope.decode(file, to: zip, password: password)
        let root = directory.appendingPathComponent("payload", isDirectory: true)
        let names = try PortableZIP.extract(zip, to: root)
        let required: Set<String> = ["database.sqlite", "settings.json", "manifest.json"]
        guard required.isSubset(of: names) else { throw PortableDataError.invalidFormat }
        let manifest = try JSONDecoder().decode(PortableManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        guard manifest.format == 1, (1...AndroidExchangeSchema.current).contains(manifest.schema) else {
            throw PortableDataError.unsupportedSchema
        }
        guard Set(manifest.files.keys) == names.subtracting(["manifest.json"]) else {
            throw PortableDataError.invalidFormat
        }
        for (name, expected) in manifest.files {
            let digest = try PortableFiles.digest(root.appendingPathComponent(name), limit: PortableLimits.entry(name))
            guard digest == expected else { throw PortableDataError.invalidFormat }
        }
        let settings = try PortableSettings.decode(Data(contentsOf: root.appendingPathComponent("settings.json")))
        try AndroidExchangeSchema.load().importDatabase(root.appendingPathComponent("database.sqlite"),
            version: manifest.schema, into: database)
        try database.read { db in
            try validateBaseCurrency(settings, in: db)
            try PortableLedger.validate(db)
            var assets: [String: PortableRecord] = [:]
            for row in manifest.visual_assets {
                guard let id = row["id"] ?? nil, assets.updateValue(row, forKey: id) == nil else {
                    throw PortableDataError.invalidImage
                }
            }
            var matched = required
            try PortableLedger.rows("visual_assets", in: db) { row in
                let model = try VisualAssetRecord(row: row).visualModel()
                guard PortableLimits.assetPath(model.relativePath), names.contains(model.relativePath),
                      try assets.removeValue(forKey: model.id) == PortableLedger.record(row) else {
                    throw PortableDataError.invalidImage
                }
                try validateImage(model, at: root.appendingPathComponent(model.relativePath))
                matched.insert(model.relativePath)
            }
            guard matched == names, assets.isEmpty else { throw PortableDataError.invalidImage }
        }
        return settings
    }

    private static func validateBaseCurrency(_ settings: PortableSettings, in db: Database) throws {
        let code = settings.base_currency_code ?? EntryDraft.defaultBaseCurrencyCode
        guard let currency = try CurrencyRecord.fetchOne(db, key: code), currency.asset_type == "FIAT" else {
            throw PortableDataError.invalidFormat
        }
        if currency.is_enabled != 1 {
            guard let fallback = try CurrencyRecord.fetchOne(db, key: EntryDraft.defaultBaseCurrencyCode),
                  fallback.asset_type == "FIAT", fallback.is_enabled == 1 else { throw PortableDataError.invalidFormat }
        }
    }

    private static func validateImage(_ asset: VisualAsset, at url: URL) throws {
        let digest = try PortableFiles.digest(url, limit: VisualLimits.outputBytes)
        guard digest.size == asset.byteSize, digest.sha256 == asset.sha256 else { throw PortableDataError.invalidImage }
        let data = try Data(contentsOf: url)
        guard data.count >= 20, data.prefix(4) == Data("RIFF".utf8), Int(data.zip32(4)) + 8 == data.count,
              data[8..<12] == Data("WEBP".utf8) else { throw PortableDataError.invalidImage }
        let allowed: Set<String> = ["VP8X", "VP8L", "VP8 ", "ALPH", "ICCP"]
        var offset = 12
        var chunks = Set<String>()
        while offset < data.count {
            guard offset + 8 <= data.count, let type = String(data: data[offset..<(offset + 4)], encoding: .ascii),
                  allowed.contains(type), chunks.insert(type).inserted else {
                throw PortableDataError.invalidImage
            }
            let length = Int(data.zip32(offset + 4))
            offset += 8 + length + length % 2
            guard offset <= data.count else { throw PortableDataError.invalidImage }
        }
        guard chunks.contains("VP8L") != chunks.contains("VP8 "),
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == "org.webmproject.webp",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == asset.width,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == asset.height,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else {
            throw PortableDataError.invalidImage
        }
    }
}
