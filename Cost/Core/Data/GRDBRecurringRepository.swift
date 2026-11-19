import GRDB

extension GRDBLedgerRepository: RecurringRepository {
    func recurringRules() async throws -> [RecurringRule] {
        try await read { db in
            let rows = try RecurringRuleRecord.fetchAll(db, sql: "SELECT * FROM recurring_rules ORDER BY is_enabled DESC, name, id")
            let tags = Dictionary(grouping: try RecurringRuleTagRecord.fetchAll(db), by: \.rule_id)
            return try rows.map { try $0.model(tags: Set(tags[$0.id, default: []].map(\.tag_id))) }
        }
    }

    func saveRecurringRule(id: String, content: RecurringContent, expectedVersion: Int64?, at timestamp: Int64) async throws {
        try content.schedule.validate()
        try await write { db in
            let previous = try RecurringRuleRecord.fetchOne(db, key: id)
            guard previous?.rule_version == expectedVersion else { throw LedgerError.conflict }
            let oldTags = try Self.recurringTags(db, id: id)
            if let issue = try Self.recurringReferenceIssue(db, content: content, keeping: previous, previousTags: oldTags) { throw issue }
            let version = try Self.incrementRecurringCounter(previous?.rule_version ?? 0)
            let now = max(timestamp, previous?.updated_at_epoch_millis ?? timestamp)
            let schedule = content.schedule
            let target = previous == nil ? schedule.startDay : try schedule.localDay(at: now)
            let row = RecurringRuleRecord(id: id, name: content.name, is_enabled: previous?.is_enabled ?? 1,
                start_local_epoch_day: schedule.startDay, end_local_epoch_day: schedule.endDay,
                scheduled_local_time_minutes: Int64(schedule.minutes), zone_id: schedule.zoneID,
                next_occurrence_at: try schedule.occurrence(onOrAfter: target), last_evaluated_at: previous?.last_evaluated_at,
                rule_version: version, catch_up_policy: content.catchUp.rawValue, frequency: schedule.frequency.rawValue,
                interval_value: Int64(schedule.intervalValue), interval_unit: schedule.intervalUnit?.rawValue,
                weekdays_mask: Int64(schedule.weekdaysMask), day_of_month: schedule.dayOfMonth.map { Int64($0) },
                month_of_year: schedule.monthOfYear.map { Int64($0) }, month_day_policy: schedule.monthPolicy.rawValue,
                transaction_type: content.type.rawValue, amount_minor: content.amount.minorUnits, amount_scale: Int64(content.amount.scale),
                currency_code: content.amount.currencyCode.rawValue, category_id: content.categoryID, account_id: content.accountID,
                note: content.note, created_at_epoch_millis: previous?.created_at_epoch_millis ?? now, updated_at_epoch_millis: now)
            if previous == nil { try row.insert(db) } else { try row.update(db) }
            try db.execute(sql: "DELETE FROM recurring_rule_tags WHERE rule_id = ?", arguments: [id])
            for tag in content.tagIDs.sorted() { try RecurringRuleTagRecord(rule_id: id, tag_id: tag).insert(db) }
        }
    }

    func setRecurringEnabled(_ rule: RecurringRule, enabled: Bool, catchUp: RecurringCatchUp, at timestamp: Int64) async throws {
        try await write { db in
            guard var row = try RecurringRuleRecord.fetchOne(db, key: rule.id), row.rule_version == rule.version else { throw LedgerError.conflict }
            guard (row.is_enabled == 1) != enabled || row.catch_up_policy != catchUp.rawValue else { return }
            row.is_enabled = enabled ? 1 : 0
            row.catch_up_policy = catchUp.rawValue
            row.rule_version = try Self.incrementRecurringCounter(row.rule_version)
            row.updated_at_epoch_millis = max(timestamp, row.updated_at_epoch_millis)
            if enabled && row.next_occurrence_at == nil {
                let schedule = rule.content.schedule
                row.next_occurrence_at = try schedule.occurrence(onOrAfter: schedule.localDay(at: row.updated_at_epoch_millis))
            }
            try row.update(db)
        }
    }

    func deleteRecurringRule(_ rule: RecurringRule) async throws {
        try await write { db in
            guard let row = try RecurringRuleRecord.fetchOne(db, key: rule.id), row.rule_version == rule.version else { throw LedgerError.conflict }
            _ = try row.delete(db)
        }
    }

    func recurringFailures(limit: Int, after cursor: RecurringExecution?) async throws -> [RecurringExecution] {
        try await read { db in
            try RecurringExecutionRecord.fetchAll(db, sql: """
                SELECT * FROM recurring_executions WHERE status IN ('FAILED_RETRYABLE', 'FAILED_FINAL')
                AND (? IS NULL OR (scheduled_at, id) < (?, ?))
                ORDER BY scheduled_at DESC, id DESC LIMIT ?
                """, arguments: [cursor?.scheduledAt, cursor?.scheduledAt, cursor?.id, min(max(1, limit), 200)])
                .map { try $0.model() }
        }
    }

    func dueRecurringWork(at timestamp: Int64, excluding: Set<String>) async throws -> RecurringWork? {
        try await read { db in
            // At most the number of excluded rules can precede the first eligible row.
            let rows = try RecurringRuleRecord.fetchAll(db, sql: """
                SELECT * FROM recurring_rules WHERE is_enabled = 1 AND next_occurrence_at <= ?
                ORDER BY next_occurrence_at, id LIMIT ?
                """, arguments: [timestamp, excluding.count + 1])
            guard let row = rows.first(where: { !excluding.contains($0.id) }), let instant = row.next_occurrence_at else { return nil }
            let rule = try row.model(tags: Self.recurringTags(db, id: row.id))
            return try RecurringWork(rule: rule, scheduledAt: instant, execution: Self.recurringExecution(db, id: row.id, instant: instant)?.model())
        }
    }

    func recurringWork(for execution: RecurringExecution) async throws -> RecurringWork? {
        try await read { db in
            guard let row = try RecurringRuleRecord.fetchOne(db, key: execution.ruleID),
                  let current = try Self.recurringExecution(db, id: row.id, instant: execution.scheduledAt)?.model(),
                  current == execution, current.status.needsAttention else { return nil }
            let rule = try row.model(tags: Self.recurringTags(db, id: row.id))
            return RecurringWork(rule: rule, scheduledAt: current.scheduledAt, execution: current)
        }
    }

    func commitRecurringWork(_ work: RecurringWork, outcome: RecurringOutcome, at timestamp: Int64, isManual: Bool) async throws -> RecurringStatus? {
        try await write { db in
            guard var rule = try RecurringRuleRecord.fetchOne(db, key: work.rule.id), rule.rule_version == work.rule.version else { return nil }
            let atCursor = rule.next_occurrence_at == work.scheduledAt
            if !isManual && (!atCursor || rule.is_enabled != 1 || work.scheduledAt > timestamp) { return nil }
            let prior = try Self.recurringExecution(db, id: rule.id, instant: work.scheduledAt)
            let previous = try prior?.model()
            guard previous == work.execution else { return nil }
            if isManual && previous?.status.needsAttention != true { return nil }
            let now = max(timestamp, rule.created_at_epoch_millis, prior?.updated_at_epoch_millis ?? timestamp)

            let status: RecurringStatus
            if let previous, previous.status.isHandled || (!isManual && previous.status == .failed) {
                status = previous.status
            } else {
                let decision = try Self.recordRecurringOutcome(db, work: work, outcome: outcome, rule: rule)
                status = decision.status
                let row = RecurringExecutionRecord(id: prior?.id ?? work.requestKey, rule_id: rule.id,
                    scheduled_at: work.scheduledAt, status: status.rawValue, transaction_id: decision.transactionID,
                    attempt_count: try Self.incrementRecurringCounter(prior?.attempt_count ?? 0), last_error: decision.issue?.rawValue,
                    created_at_epoch_millis: prior?.created_at_epoch_millis ?? now, updated_at_epoch_millis: now)
                if prior == nil { try row.insert(db) } else { try row.update(db) }
            }
            if atCursor {
                if status != .retryable { rule.next_occurrence_at = try work.rule.content.schedule.next(after: work.scheduledAt) }
                rule.last_evaluated_at = max(now, rule.last_evaluated_at ?? now)
                try rule.update(db)
            }
            return status
        }
    }

    private static func recordRecurringOutcome(_ db: Database, work: RecurringWork, outcome: RecurringOutcome,
                                               rule: RecurringRuleRecord) throws -> (status: RecurringStatus, transactionID: String?, issue: RecurringIssue?) {
        if let existing = try find(db, requestKey: work.requestKey) {
            guard existing.source == .recurring, existing.sourceID == rule.id else { throw LedgerError.conflict }
            return (.created, existing.id, nil)
        }
        if case .skip = outcome { return (.skipped, nil, nil) }
        guard rule.is_enabled == 1 else { throw LedgerError.conflict }
        let content = work.rule.content
        if let issue = try recurringReferenceIssue(db, content: content) { return (.failed, nil, issue) }
        switch outcome {
        case .skip: return (.skipped, nil, nil)
        case let .failure(issue, retryable): return (retryable ? .retryable : .failed, nil, issue)
        case let .ready(transaction):
            guard transaction.source == .recurring, transaction.sourceID == rule.id, transaction.requestKey == work.requestKey,
                  transaction.occurredAt.epochMillis == work.scheduledAt, transaction.occurredAt.zoneID == content.schedule.zoneID,
                  transaction.categoryID == content.categoryID, transaction.accountID == content.accountID,
                  transaction.tagIDs == content.tagIDs, transaction.type == content.type, transaction.note == content.note,
                  transaction.deletedAt == nil, try transaction.original == content.amount.rescaled(to: transaction.original.scale)
            else { throw LedgerError.conflict }
            guard let base = try CurrencyRecord.fetchOne(db, key: transaction.convertedBase.currencyCode.rawValue),
                  base.is_enabled == 1, base.asset_type == AssetType.fiat.rawValue else { return (.failed, nil, .currencyUnavailable) }
            guard base.default_scale == Int64(transaction.convertedBase.scale) else { throw LedgerError.conflict }
            try insertTransaction(db, transaction)
            return (.created, transaction.id, nil)
        }
    }

    private static func recurringReferenceIssue(_ db: Database, content: RecurringContent, keeping previous: RecurringRuleRecord? = nil,
                                                previousTags: Set<String> = []) throws -> RecurringIssue? {
        let code = content.amount.currencyCode.rawValue
        guard let currency = try CurrencyRecord.fetchOne(db, key: code), currency.asset_type == AssetType.fiat.rawValue,
              currency.is_enabled == 1 || previous?.currency_code == code else { return .currencyUnavailable }
        guard let category = try CategoryRecord.fetchOne(db, key: content.categoryID), category.transaction_type == content.type.rawValue,
              category.is_archived == 0 || previous?.category_id == category.id,
              let account = try AccountRecord.fetchOne(db, key: content.accountID),
              account.is_archived == 0 || previous?.account_id == account.id else { return .referenceUnavailable }
        for id in content.tagIDs {
            guard let tag = try TagRecord.fetchOne(db, key: id), tag.is_archived == 0 || previousTags.contains(id) else { return .referenceUnavailable }
        }
        return nil
    }

    private static func recurringTags(_ db: Database, id: String) throws -> Set<String> {
        try Set(String.fetchAll(db, sql: "SELECT tag_id FROM recurring_rule_tags WHERE rule_id = ?", arguments: [id]))
    }

    private static func recurringExecution(_ db: Database, id: String, instant: Int64) throws -> RecurringExecutionRecord? {
        try RecurringExecutionRecord.fetchOne(db, sql: "SELECT * FROM recurring_executions WHERE rule_id = ? AND scheduled_at = ?", arguments: [id, instant])
    }

    private static func incrementRecurringCounter(_ value: Int64) throws -> Int64 {
        let next = value.addingReportingOverflow(1)
        guard !next.overflow else { throw LedgerError.conflict }
        return next.partialValue
    }
}

private extension RecurringRuleRecord {
    func model(tags: Set<String>) throws -> RecurringRule {
        let schedule = try RecurringSchedule(startDay: start_local_epoch_day, endDay: end_local_epoch_day,
            minutes: Int(scheduled_local_time_minutes), zoneID: zone_id, frequency: storedEnum(frequency, as: RecurringFrequency.self),
            intervalValue: Int(interval_value), intervalUnit: interval_unit.map { try storedEnum($0, as: RecurringIntervalUnit.self) },
            weekdaysMask: Int(weekdays_mask), dayOfMonth: day_of_month.map { Int($0) }, monthOfYear: month_of_year.map { Int($0) },
            monthPolicy: storedEnum(month_day_policy, as: RecurringMonthPolicy.self))
        try schedule.validate()
        let content = try RecurringContent(name: name, type: storedEnum(transaction_type, as: TransactionType.self),
            amount: Money(minorUnits: amount_minor, currencyCode: CurrencyCode(currency_code), scale: Int(amount_scale)),
            categoryID: category_id, accountID: account_id, note: note, tagIDs: tags, schedule: schedule,
            catchUp: storedEnum(catch_up_policy, as: RecurringCatchUp.self))
        return RecurringRule(id: id, content: content, isEnabled: is_enabled == 1, nextOccurrence: next_occurrence_at,
            version: rule_version, createdAt: created_at_epoch_millis)
    }
}

private extension RecurringExecutionRecord {
    func model() throws -> RecurringExecution {
        try RecurringExecution(id: id, ruleID: rule_id, scheduledAt: scheduled_at, status: storedEnum(status, as: RecurringStatus.self),
            transactionID: transaction_id, attempts: attempt_count, issue: last_error.map { try storedEnum($0, as: RecurringIssue.self) })
    }
}
