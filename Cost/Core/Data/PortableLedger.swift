import Foundation
import GRDB

typealias PortableRecord = [String: String?]

struct AndroidExchangeSchema: Decodable, Sendable {
    static let current = 10
    let statements: [String]
    let columns: [String: [String: [String]]]

    static func load() throws -> Self {
        try JSONDecoder().decode(Self.self, from: DatabaseResources.data("AndroidExchangeSchema", extension: "json"))
    }

    func makeDatabase(at url: URL) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            for statement in statements { try db.execute(sql: statement) }
        }
        return queue
    }

    func importDatabase(_ url: URL, version: Int, into target: DatabaseQueue) throws {
        guard let history = columns[String(version)] else { throw PortableDataError.unsupportedSchema }
        var configuration = Configuration()
        configuration.readonly = true
        configuration.prepareDatabase { try $0.execute(sql: "PRAGMA trusted_schema = OFF") }
        let source = try DatabaseQueue(path: url.path, configuration: configuration)
        try source.read { db in
            guard try Int.fetchOne(db, sql: "PRAGMA user_version") == version,
                  try String.fetchAll(db, sql: "PRAGMA integrity_check(1)") == ["ok"] else {
                throw PortableDataError.unsupportedSchema
            }
            let rows = try Row.fetchAll(db, sql: "PRAGMA main.table_list")
            let tables = Set(rows.compactMap { row -> String? in
                let type: String = row["type"]
                let name: String = row["name"]
                return type == "view" || name == "sqlite_schema" ? nil : name
            })
            let expected = Set(history.keys).subtracting(["restore_state"])
            guard expected.isSubset(of: tables),
                  tables.isSubset(of: expected.union(["restore_state", "room_master_table", "android_metadata"])),
                  rows.allSatisfy({ row in
                      let type: String = row["type"]
                      return type == "table" || type == "view"
                  }) else { throw PortableDataError.unsupportedSchema }
            try target.write { output in
                for table in PortableLedger.tables where expected.contains(table) {
                    guard let names = history[table],
                          Set(try db.columns(in: table).map(\.name)) == Set(names) else {
                        throw PortableDataError.unsupportedSchema
                    }
                    try PortableLedger.copy(table, from: db, to: output, columns: names)
                }
                try PortableLedger.checkReferences(output)
            }
        }
    }
}

enum PortableLedger {
    static let tables = [
        "currencies", "visual_assets", "categories", "accounts", "tags", "transactions",
        "account_fund_openings", "account_transfers", "transaction_tags", "fx_quotes", "crypto_price_quotes",
        "quick_templates", "quick_template_tags", "recurring_rules", "recurring_rule_tags", "recurring_executions",
        "anomaly_feedback",
    ]

    struct Table {
        let name: String
        let columns: [String]
        let integers: Set<String>
        let insert: Statement

        init(_ name: String, db: Database, selecting names: [String]? = nil) throws {
            self.name = name
            let definitions = try db.columns(in: name)
            let columns = names ?? definitions.map(\.name)
            self.columns = columns
            integers = Set(definitions.filter { $0.type.uppercased() == "INTEGER" }.map(\.name))
            let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ",")
            insert = try db.makeStatement(sql: "INSERT INTO \(quote(name)) (\(columns.map(quote).joined(separator: ","))) VALUES (\(placeholders))")
        }

        func add(_ record: PortableRecord) throws {
            guard record.count == columns.count else { throw PortableDataError.invalidFormat }
            let values = try columns.map { column -> DatabaseValue in
                guard let field = record[column] else { throw PortableDataError.invalidFormat }
                guard let field else { return .null }
                if integers.contains(column) {
                    guard let value = Int64(field), String(value) == field else { throw PortableDataError.invalidFormat }
                    return value.databaseValue
                }
                return field.databaseValue
            }
            try insert.execute(arguments: StatementArguments(values))
        }

        func add(_ row: Row, replacingPath path: String? = nil) throws {
            let values = try columns.map { column -> DatabaseValue in
                if column == "relative_path", let path { return path.databaseValue }
                let value: DatabaseValue = row[column]
                switch value.storage {
                case .null: break
                case .int64 where integers.contains(column): break
                case .string where !integers.contains(column): break
                default: throw PortableDataError.invalidFormat
                }
                return value
            }
            try insert.execute(arguments: StatementArguments(values))
        }
    }

    static func quote(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func rows(_ table: String, in db: Database, _ handle: (Row) throws -> Void) throws {
        let order = table == "categories" ? " ORDER BY parent_id IS NOT NULL, id" : ""
        let cursor = try Row.fetchCursor(db, sql: "SELECT * FROM \(quote(table))\(order)")
        var count = 0
        while let row = try cursor.next() {
            if count.isMultiple(of: 1024) { try Task.checkCancellation() }
            count += 1
            guard count <= 500_000 else { throw PortableDataError.tooLarge }
            try handle(row)
        }
    }

    static func record(_ row: Row) throws -> PortableRecord {
        var result: PortableRecord = [:]
        for (column, value) in row {
            switch value.storage {
            case .null: result.updateValue(nil, forKey: column)
            case .int64(let integer): result.updateValue(String(integer), forKey: column)
            case .string(let string): result.updateValue(string, forKey: column)
            default: throw PortableDataError.invalidFormat
            }
        }
        return result
    }

    static func copy(_ table: String, from source: Database, to target: Database,
                     columns: [String]? = nil, images: [String: String] = [:]) throws {
        let writer = try Table(table, db: target, selecting: columns)
        try rows(table, in: source) { row in
            let path: String? = table == "visual_assets" ? images[row["id"] as String] : nil
            try writer.add(row, replacingPath: path)
        }
    }

    static func clear(_ db: Database) throws {
        for table in tables.reversed() {
            if table == "categories" { try db.execute(sql: "DELETE FROM categories WHERE parent_id IS NOT NULL") }
            try db.execute(sql: "DELETE FROM \(quote(table))")
        }
    }

    static func checkReferences(_ db: Database) throws {
        guard try Row.fetchOne(db, sql: "PRAGMA foreign_key_check") == nil else {
            throw PortableDataError.conflictingRecords
        }
    }

    static func makeStaging(at url: URL) throws -> DatabaseQueue {
        let stage = try DatabaseQueue(path: url.path, configuration: AppDatabase.configuration())
        let data = try DatabaseResources.data("CostSchemaV1", extension: "sql")
        guard let sql = String(data: data, encoding: .utf8) else { throw LedgerError.missingResource }
        try stage.write { try $0.execute(sql: sql) }
        return stage
    }

    static func validate(_ db: Database) throws {
        try models(CurrencyRecord.self, in: db) { _ = try $0.model() }
        try models(CategoryRecord.self, in: db) { _ = try $0.model() }
        try models(AccountRecord.self, in: db) { _ = try $0.model() }
        try models(TagRecord.self, in: db) { _ = try $0.model() }
        try models(VisualAssetRecord.self, in: db) { _ = try $0.visualModel() }
        try models(FiatQuoteRecord.self, in: db) { _ = try $0.model() }
        try models(MarketQuoteRecord.self, in: db) { _ = try $0.model() }
        try models(TransactionRecord.self, in: db) {
            let transaction = try $0.model(tagIDs: [])
            guard try OccurredAt(epochMillis: transaction.occurredAt.epochMillis,
                zoneID: transaction.occurredAt.zoneID).localEpochDay == transaction.occurredAt.localEpochDay else {
                throw PortableDataError.invalidFormat
            }
        }
        try models(QuickTemplateRecord.self, in: db) { _ = try $0.model(tagIDs: []) }
        try models(RecurringRuleRecord.self, in: db) { _ = try $0.model(tags: []) }
        try models(RecurringExecutionRecord.self, in: db) { _ = try $0.model() }
        try models(AnomalyFeedbackRecord.self, in: db) {
            _ = try CurrencyCode($0.base_currency_code)
            _ = try storedEnum($0.feedback_type, as: AnomalyFeedbackType.self)
            _ = try storedEnum($0.kind, as: AnomalyKind.self)
            guard !$0.id.isEmpty, (0...18).contains($0.base_scale), $0.feature_version > 0,
                  $0.amount_minor_text.utf8.count <= 96 else {
                throw PortableDataError.invalidFormat
            }
            let amount = try PlainDecimal($0.amount_minor_text)
            guard Int($0.base_scale) + amount.scale <= 18, !amount.coefficient.isZero else {
                throw PortableDataError.invalidFormat
            }
        }
        try models(AccountFundOpeningRecord.self, in: db) {
            let opening = try $0.model()
            guard try String.fetchOne(db, sql: "SELECT asset_type FROM currencies WHERE code = ?",
                arguments: [opening.currencyCode.rawValue]) == "FIAT" else { throw PortableDataError.invalidFormat }
        }
        try models(AccountTransferRecord.self, in: db) { record in
            let transfer = try record.model()
            let code = transfer.currencyCode.rawValue
            guard try String.fetchOne(db, sql: "SELECT asset_type FROM currencies WHERE code = ?",
                arguments: [code]) == "FIAT" else { throw PortableDataError.invalidFormat }
            let profit = try transfer.profitTransactionID.flatMap { id in
                try TransactionRecord.fetchOne(db, key: id)?.model(tagIDs: PortableCSV.tagIDs(db, transaction: id))
            }
            if transfer.profitMinor == 0 {
                guard profit == nil || profit?.deletedAt != nil else { throw PortableDataError.invalidFormat }
            } else {
                guard let profit, try transfer.profitTransaction(existing: profit) == profit else {
                    throw PortableDataError.invalidFormat
                }
            }
        }
    }

    private static func models<T: FetchableRecord & TableRecord>(_ type: T.Type, in db: Database,
                                                                 validate: (T) throws -> Void) throws {
        let cursor = try type.fetchCursor(db)
        var count = 0
        while let record = try cursor.next() {
            if count.isMultiple(of: 1024) { try Task.checkCancellation() }
            count += 1
            try validate(record)
        }
    }
}
