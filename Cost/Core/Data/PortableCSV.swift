import Foundation
import GRDB

enum PortableCSV {
    private static let metadata = ["currencies", "categories", "accounts", "tags"]

    static func write(_ file: URL, in db: Database, columns: [String]) throws {
        let output = try PortableFiles.openOutput(file)
        defer { try? output.close() }
        var count = 0
        var size = 0
        var pending = Data()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func write(_ fields: [String?]) throws {
            let line = try encode(fields)
            size += line.count
            guard size <= PortableLimits.csv else { throw PortableDataError.tooLarge }
            pending.append(line)
            if pending.count >= PortableFiles.chunkSize {
                try output.write(contentsOf: pending)
                pending.removeAll(keepingCapacity: true)
            }
        }
        try write(header(columns))
        try PortableLedger.rows("transactions", in: db) { row in
            count += 1
            guard count <= PortableLimits.csvRows else { throw PortableDataError.tooLarge }
            let transaction = try PortableLedger.record(row)
            let context = try contextFor(transaction, in: db)
            let json = String(decoding: try encoder.encode(context), as: UTF8.self)
            try write(["1"] + columns.map { transaction[$0] ?? nil } + [json])
        }
        try output.write(contentsOf: pending)
        try output.synchronize()
    }

    static func stage(_ file: URL, into db: Database, columns: [String]) throws {
        _ = try PortableFiles.size(file, limit: PortableLimits.csv)
        let input = try Data(contentsOf: file, options: .alwaysMapped)
        let writers = try Dictionary(uniqueKeysWithValues: (metadata + ["transactions", "transaction_tags"]).map {
            ($0, try PortableLedger.Table($0, db: db))
        })
        var foundHeader = false
        let decoder = JSONDecoder()
        try parse(input) { cells in
            if !foundHeader {
                guard cells == header(columns) else { throw PortableDataError.invalidFormat }
                foundHeader = true
                return
            }
            guard cells.first == "1", cells.count == columns.count + 2,
                  let context = cells.last ?? nil else { throw PortableDataError.invalidFormat }
            let record = Dictionary(uniqueKeysWithValues: zip(columns, cells.dropFirst().dropLast()))
            let references = try decoder.decode([String: [PortableRecord]].self, from: Data(context.utf8))
            guard Set(references.keys) == Set(metadata), references.values.allSatisfy({ $0.count <= 100 }) else {
                throw PortableDataError.invalidFormat
            }
            for table in metadata {
                let records = references[table]!
                let ordered = table == "categories" ? records.sorted {
                    ($0["parent_id"] ?? nil) == nil && ($1["parent_id"] ?? nil) != nil
                } : records
                for row in ordered {
                    if table == "categories" || table == "accounts" {
                        guard row == withoutImages(row, account: table == "accounts") else {
                            throw PortableDataError.invalidFormat
                        }
                    }
                    _ = try merge(row, table: writers[table]!, in: db)
                }
            }
            let id = try required("id", in: record)
            let tags = try Set(references["tags"]!.map { try required("id", in: $0) })
            if try merge(record, table: writers["transactions"]!, in: db) {
                for tag in tags { try writers["transaction_tags"]!.add(["transaction_id": id, "tag_id": tag]) }
            } else {
                guard try tagIDs(db, transaction: id) == tags else { throw PortableDataError.conflictingRecords }
            }
        }
        guard foundHeader else { throw PortableDataError.invalidFormat }
        try PortableLedger.checkReferences(db)
        try PortableLedger.validate(db)
    }

    static func merge(_ source: Database, into target: Database) throws -> PortableDataOutcome {
        var imported = 0
        var skipped = 0
        for table in metadata + ["transactions", "transaction_tags"] {
            let writer = try PortableLedger.Table(table, db: target)
            try PortableLedger.rows(table, in: source) { row in
                let record = try PortableLedger.record(row)
                let inserted = try merge(record, table: writer, in: target, ignoreImageReferences: true)
                if table == "transactions" {
                    if inserted { imported += 1 }
                    else {
                        let id = try required("id", in: record)
                        guard try tagIDs(source, transaction: id) == tagIDs(target, transaction: id) else {
                            throw PortableDataError.conflictingRecords
                        }
                        skipped += 1
                    }
                }
            }
        }
        try PortableLedger.checkReferences(target)
        return PortableDataOutcome(imported: imported, skipped: skipped, settingsPending: false)
    }

    static func tagIDs(_ db: Database, transaction: String) throws -> Set<String> {
        try Set(String.fetchAll(db, sql: "SELECT tag_id FROM transaction_tags WHERE transaction_id = ?", arguments: [transaction]))
    }

    private static func contextFor(_ transaction: PortableRecord, in db: Database) throws -> [String: [PortableRecord]] {
        let id = try required("id", in: transaction)
        let category = try find("categories", id: required("category_id", in: transaction), in: db)
        var categories: [PortableRecord] = []
        if let parent = category["parent_id"] ?? nil {
            categories.append(try withoutImages(find("categories", id: parent, in: db)))
        }
        categories.append(withoutImages(category))
        let account = try find("accounts", id: required("account_id", in: transaction), in: db)
        var codes = try Set(["original_currency_code", "base_currency_code"].map { try required($0, in: transaction) })
        if let code = account["currency_code"] ?? nil { codes.insert(code) }
        let currencies = try codes.sorted().map { try find("currencies", id: $0, key: "code", in: db) }
        let rows = try Row.fetchAll(db, sql: """
            SELECT tags.* FROM tags JOIN transaction_tags ON tags.id = transaction_tags.tag_id
            WHERE transaction_id = ? ORDER BY tags.id LIMIT 101
            """, arguments: [id])
        guard rows.count <= 100 else { throw PortableDataError.tooLarge }
        return ["categories": categories, "accounts": [withoutImages(account, account: true)],
                "currencies": currencies, "tags": try rows.map(PortableLedger.record)]
    }

    private static func find(_ table: String, id: String, key: String = "id", in db: Database) throws -> PortableRecord {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM \(table) WHERE \(key) = ?", arguments: [id]) else {
            throw PortableDataError.invalidFormat
        }
        return try PortableLedger.record(row)
    }

    private static func required(_ key: String, in row: PortableRecord) throws -> String {
        guard let result = row[key] ?? nil else { throw PortableDataError.invalidFormat }
        return result
    }

    private static func withoutImages(_ record: PortableRecord, account: Bool = false) -> PortableRecord {
        var result = record
        result.updateValue(nil, forKey: "icon_asset_id")
        result.updateValue(nil, forKey: "background_asset_id")
        if record["icon_source"] == .some("IMAGE") { result.updateValue("BUILT_IN", forKey: "icon_source") }
        if account { result.updateValue("0", forKey: "is_default") }
        return result
    }

    private static func merge(_ record: PortableRecord, table: PortableLedger.Table, in db: Database,
                              ignoreImageReferences: Bool = false) throws -> Bool {
        let keys: [String]
        switch table.name {
        case "currencies": keys = ["code"]
        case "transaction_tags": keys = ["transaction_id", "tag_id"]
        default: keys = ["id"]
        }
        let values = try keys.map { try required($0, in: record) }
        let whereClause = keys.map { "\($0) = ?" }.joined(separator: " AND ")
        guard Set(record.keys) == Set(table.columns) else { throw PortableDataError.invalidFormat }
        if let row = try Row.fetchOne(db, sql: "SELECT * FROM \(table.name) WHERE \(whereClause)", arguments: StatementArguments(values)) {
            let current = try PortableLedger.record(row)
            if table.name == "currencies" {
                guard record["asset_type"] == current["asset_type"] else { throw PortableDataError.conflictingRecords }
                return false
            }
            let compared = ignoreImageReferences && ["accounts", "categories"].contains(table.name)
                ? withoutImages(current, account: table.name == "accounts") : current
            guard compared == record else { throw PortableDataError.conflictingRecords }
            return false
        }
        try table.add(record)
        return true
    }

    private static func header(_ columns: [String]) -> [String?] {
        (["cost_csv_v1"] + columns + ["context_json"]).map(Optional.some)
    }

    static func encode(_ cells: [String?]) throws -> Data {
        let fields = try cells.map { value in
            guard let value else { return "\"\\N\"" }
            guard value.utf16.count < PortableLimits.csvCellUTF16 else { throw PortableDataError.tooLarge }
            return "\"'" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return Data((fields.joined(separator: ",") + "\r\n").utf8)
    }

    static func parse(_ bytes: Data, _ consume: ([String?]) throws -> Void) throws {
        var index = bytes.startIndex
        var rows = 0
        while index < bytes.endIndex {
            if rows.isMultiple(of: 1024) { try Task.checkCancellation() }
            var cells: [String?] = []
            while true {
                guard index < bytes.endIndex, bytes[index] == 34, cells.count < 64 else {
                    throw PortableDataError.invalidFormat
                }
                index += 1
                var field = Data()
                while true {
                    guard index < bytes.endIndex else { throw PortableDataError.invalidFormat }
                    let byte = bytes[index]
                    index += 1
                    if byte == 34 {
                        guard index < bytes.endIndex, bytes[index] == 34 else { break }
                        index += 1
                    }
                    field.append(byte)
                    guard field.count <= 3 * PortableLimits.csvCellUTF16 else { throw PortableDataError.tooLarge }
                }
                if field == Data([92, 78]) {
                    cells.append(nil)
                } else {
                    guard field.first == 39, let value = String(data: field.dropFirst(), encoding: .utf8) else {
                        throw PortableDataError.invalidFormat
                    }
                    guard value.utf16.count < PortableLimits.csvCellUTF16 else { throw PortableDataError.tooLarge }
                    cells.append(value)
                }
                if index == bytes.endIndex { break }
                let delimiter = bytes[index]
                index += 1
                if delimiter == 44 { continue }
                if delimiter == 13 {
                    guard index < bytes.endIndex, bytes[index] == 10 else { throw PortableDataError.invalidFormat }
                    index += 1
                } else if delimiter != 10 { throw PortableDataError.invalidFormat }
                break
            }
            rows += 1
            guard rows <= PortableLimits.csvRows + 1 else { throw PortableDataError.tooLarge }
            try consume(cells)
        }
    }
}
