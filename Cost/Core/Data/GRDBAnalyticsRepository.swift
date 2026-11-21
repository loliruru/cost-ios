import GRDB

/// SQLite calls this aggregate with INTEGER values and receives a lossless TEXT subtotal.
struct FrozenMinorSum: DatabaseAggregate {
    private var total = DecimalInteger.zero
    private var subtotal: Int64 = 0

    static let function = DatabaseFunction("cost_minor_sum", argumentCount: 1, pure: true, aggregate: Self.self)

    mutating func step(_ dbValues: [DatabaseValue]) throws {
        guard case .int64(let amount) = dbValues[0].storage, amount > 0 else {
            throw LedgerError.invalidSnapshot
        }
        let next = subtotal.addingReportingOverflow(amount)
        if next.overflow {
            total = total.adding(DecimalInteger(String(subtotal)))
            subtotal = amount
        } else {
            subtotal = next.partialValue
        }
    }

    func finalize() -> (any DatabaseValueConvertible)? {
        total.adding(DecimalInteger(String(subtotal))).description
    }
}

struct GRDBAnalyticsRepository: StatisticsRepository, AnomalyRepository {
    let database: AppDatabase

    func observeStatistics(range: StatisticsRange, today: Int64, currency: CurrencyCode)
        -> AsyncThrowingStream<StatisticsInput, Error> {
        observe { db in
            let todayRange = (today - 1)..<(today + 1)
            let periods = [range.days, range.previous, range.lastYear, todayRange]
            var currencies: Set<CurrencyCode> = [currency]
            for period in periods {
                let codes = try String.fetchAll(db, sql: """
                    SELECT c.code FROM currencies c
                    WHERE EXISTS (
                        SELECT 1 FROM transactions t
                        WHERE t.base_currency_code = c.code AND t.deleted_at_epoch_millis IS NULL
                          AND t.occurred_local_epoch_day >= ? AND t.occurred_local_epoch_day < ?
                    )
                    """, arguments: [period.lowerBound, period.upperBound])
                currencies.formUnion(try codes.map { try CurrencyCode($0) })
            }
            let scale = try Int.fetchOne(db, sql: "SELECT default_scale FROM currencies WHERE code = ?",
                                         arguments: [currency.rawValue]) ?? 0
            guard (0...18).contains(scale) else { throw LedgerError.invalidSnapshot }
            return try StatisticsInput(
                currencies: currencies.sorted { $0.rawValue < $1.rawValue }, minimumScale: scale,
                current: Self.dailyTotals(db, currency, range.days),
                previous: Self.dailyTotals(db, currency, range.previous),
                lastYear: Self.dailyTotals(db, currency, range.lastYear),
                today: Self.dailyTotals(db, currency, todayRange),
                categories: Self.categoryTotals(db, currency, range.days),
                previousCategories: Self.categoryTotals(db, currency, range.previous))
        }
    }

    func observeAnomalyInput(_ request: AnomalyRequest) -> AsyncThrowingStream<AnomalyInput, Error> {
        observe { db in
            let limit = DetectSpendingAnomalies.sampleLimit + 1
            let arguments: StatementArguments = [request.currency.rawValue,
                request.sampleRange.lowerBound, request.sampleRange.upperBound, limit]
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.id, t.occurred_local_epoch_day, t.category_id, c.name,
                       CAST(t.converted_base_amount_minor AS TEXT) AS minor, t.base_scale
                FROM transactions t JOIN categories c ON t.category_id = c.id
                WHERE \(Self.expenseSampleFilter)
                ORDER BY t.occurred_local_epoch_day DESC
                LIMIT ?
                """, arguments: arguments)
            let samples = try rows.map { row in
                try AnomalyTransaction(id: row["id"], day: row["occurred_local_epoch_day"], categoryID: row["category_id"],
                    categoryName: row["name"], amount: Self.amount(row))
            }
            if samples.count == limit { return AnomalyInput(transactions: samples, daily: [], feedback: []) }
            let daily = try Row.fetchAll(db, sql: """
                SELECT t.occurred_local_epoch_day, t.category_id, t.base_scale,
                       cost_minor_sum(t.converted_base_amount_minor) AS minor
                FROM transactions t
                WHERE \(Self.expenseSampleFilter)
                GROUP BY t.occurred_local_epoch_day, t.category_id, t.base_scale
                LIMIT ?
                """, arguments: arguments).map { row in
                    try AnomalyDay(day: row["occurred_local_epoch_day"], categoryID: row["category_id"], amount: Self.amount(row))
                }
            let records = try AnomalyFeedbackRecord.fetchAll(db, sql: """
                SELECT * FROM anomaly_feedback WHERE base_currency_code = ?
                """, arguments: [request.currency.rawValue])
            return try AnomalyInput(transactions: samples, daily: daily, feedback: records.map { try Self.feedback($0) })
        }
    }

    func saveAnomalyFeedback(_ feedback: AnomalyFeedback) async throws {
        let amount = feedback.amount
        guard !amount.units.isZero, (0...18).contains(amount.scale) else { throw LedgerError.invalidSnapshot }
        try await GRDBLedgerRepository(database: database).write { db in
            let row = AnomalyFeedbackRecord(id: feedback.id, feedback_type: feedback.type.rawValue,
                kind: feedback.kind.rawValue, category_id: feedback.categoryID, base_currency_code: feedback.currency.rawValue,
                amount_minor_text: amount.units.description, base_scale: Int64(amount.scale),
                feature_version: Int64(feedback.version), created_at_epoch_millis: feedback.createdAt)
            try row.insert(db, onConflict: .replace)
        }
    }

    func observeExpenseDays(in range: SpendingFrequencyRange, currency: CurrencyCode) -> AsyncThrowingStream<Set<Int64>, Error> {
        observe { db in
            let days = range.sampleRange
            return Set(try Int64.fetchAll(db, sql: """
                SELECT DISTINCT t.occurred_local_epoch_day FROM transactions t
                WHERE \(Self.expenseSampleFilter)
                """, arguments: [currency.rawValue, days.lowerBound, days.upperBound]))
        }
    }

    func clearAnomalyFeedback() async throws {
        try await GRDBLedgerRepository(database: database).write { db in
            try db.execute(sql: "DELETE FROM anomaly_feedback")
        }
    }

    private static let expenseSampleFilter = """
        t.deleted_at_epoch_millis IS NULL AND t.transaction_type = 'EXPENSE'
        AND t.source_type <> 'RECURRING' AND t.base_currency_code = ?
        AND t.occurred_local_epoch_day >= ? AND t.occurred_local_epoch_day < ?
        """

    private func observe<Value: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> Value)
        -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    let observation = ValueObservation.tracking { db in try fetch(db) }
                    for try await value in observation.values(in: database.writer) {
                        guard !Task.isCancelled else { break }
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LedgerError.storageUnavailable)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func dailyTotals(_ db: Database, _ currency: CurrencyCode, _ days: Range<Int64>) throws -> [FrozenDayTotal] {
        try Row.fetchAll(db, sql: """
            SELECT occurred_local_epoch_day, transaction_type, base_scale, cost_minor_sum(converted_base_amount_minor) AS minor
            FROM transactions
            WHERE deleted_at_epoch_millis IS NULL AND base_currency_code = ?
              AND occurred_local_epoch_day >= ? AND occurred_local_epoch_day < ?
            GROUP BY occurred_local_epoch_day, transaction_type, base_scale
            """, arguments: [currency.rawValue, days.lowerBound, days.upperBound]).map { row in
                guard let type = TransactionType(rawValue: row["transaction_type"]) else { throw LedgerError.invalidSnapshot }
                return try FrozenDayTotal(day: row["occurred_local_epoch_day"], type: type, amount: amount(row))
            }
    }

    private static func categoryTotals(_ db: Database, _ currency: CurrencyCode, _ days: Range<Int64>) throws -> [FrozenCategoryTotal] {
        try Row.fetchAll(db, sql: """
            SELECT t.category_id, c.name, t.base_scale, cost_minor_sum(t.converted_base_amount_minor) AS minor
            FROM transactions t JOIN categories c ON t.category_id = c.id
            WHERE t.deleted_at_epoch_millis IS NULL AND t.transaction_type = 'EXPENSE' AND t.base_currency_code = ?
              AND t.occurred_local_epoch_day >= ? AND t.occurred_local_epoch_day < ?
            GROUP BY t.category_id, c.name, t.base_scale
            """, arguments: [currency.rawValue, days.lowerBound, days.upperBound]).map { row in
                try FrozenCategoryTotal(id: row["category_id"], name: row["name"], amount: amount(row))
            }
    }

    private static func amount(_ row: Row) throws -> FrozenAmount {
        let scale: Int = row["base_scale"]
        guard (0...18).contains(scale) else { throw LedgerError.invalidSnapshot }
        return FrozenAmount(units: DecimalInteger(row["minor"]), scale: scale)
    }

    private static func feedback(_ row: AnomalyFeedbackRecord) throws -> AnomalyFeedback {
        guard let type = AnomalyFeedbackType(rawValue: row.feedback_type), let kind = AnomalyKind(rawValue: row.kind),
              (0...18).contains(row.base_scale), row.amount_minor_text.utf8.count <= 96 else { throw LedgerError.invalidSnapshot }
        let amount = try PlainDecimal(row.amount_minor_text)
        let scale = Int(row.base_scale) + amount.scale
        guard scale <= 18, !amount.coefficient.isZero else { throw LedgerError.invalidSnapshot }
        return try AnomalyFeedback(id: row.id, type: type, kind: kind, categoryID: row.category_id,
            currency: CurrencyCode(row.base_currency_code), amount: FrozenAmount(units: amount.coefficient, scale: scale),
            version: Int(row.feature_version), createdAt: row.created_at_epoch_millis)
    }
}
