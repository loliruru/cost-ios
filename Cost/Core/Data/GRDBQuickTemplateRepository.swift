import GRDB

extension GRDBLedgerRepository: QuickTemplateRepository {
    private static let templateOrder = "is_archived ASC, sort_order ASC, usage_count DESC, last_used_at DESC, id ASC"

    func quickTemplates() async throws -> [QuickTemplate] {
        try await read { db in
            let rows = try QuickTemplateRecord.fetchAll(db, sql: "SELECT * FROM quick_templates ORDER BY \(Self.templateOrder)")
            let references = try QuickTemplateTagRecord.fetchAll(db)
            let tags = Dictionary(grouping: references, by: \.template_id)
            return try rows.map { try $0.model(tagIDs: Set(tags[$0.id, default: []].map(\.tag_id))) }
        }
    }

    func quickTemplate(id: String) async throws -> QuickTemplate? {
        try await read { db in
            guard let row = try QuickTemplateRecord.fetchOne(db, key: id) else { return nil }
            return try row.model(tagIDs: Self.templateTags(db, id: id))
        }
    }

    func saveQuickTemplate(id: String, content: QuickTemplateContent, sortOrder: Int64?,
                           expectedUpdatedAt: Int64?, at timestamp: Int64) async throws -> QuickTemplate {
        try await write { db in
            let existing = try QuickTemplateRecord.fetchOne(db, key: id)
            guard existing?.updated_at_epoch_millis == expectedUpdatedAt else { throw LedgerError.conflict }
            let oldTags = try Self.templateTags(db, id: id)
            try Self.validateTemplateReferences(db, content: content, keeping: existing, previousTags: oldTags)

            let order: Int64
            if let sortOrder { order = sortOrder }
            else if let existing { order = existing.sort_order }
            else {
                let maxOrder = try Int64.fetchOne(db, sql: "SELECT MAX(sort_order) FROM quick_templates") ?? 0
                let next = maxOrder.addingReportingOverflow(10)
                order = next.overflow ? maxOrder : next.partialValue
            }
            let row = QuickTemplateRecord(id: id, name: content.name, icon_key: content.iconKey,
                transaction_type: content.type.rawValue, amount_minor: content.amount.minorUnits,
                amount_scale: Int64(content.amount.scale), currency_code: content.amount.currencyCode.rawValue,
                category_id: content.categoryID, account_id: content.accountID, note: content.note, sort_order: order,
                usage_count: existing?.usage_count ?? 0, last_used_at: existing?.last_used_at, is_archived: existing?.is_archived ?? 0,
                created_at_epoch_millis: existing?.created_at_epoch_millis ?? timestamp,
                updated_at_epoch_millis: try Self.templateTimestamp(timestamp, after: existing?.updated_at_epoch_millis))
            if existing == nil { try row.insert(db) } else { try row.update(db) }
            try db.execute(sql: "DELETE FROM quick_template_tags WHERE template_id = ?", arguments: [id])
            for tagID in content.tagIDs.sorted() {
                try QuickTemplateTagRecord(template_id: id, tag_id: tagID).insert(db)
            }
            return try row.model(tagIDs: content.tagIDs)
        }
    }

    func setQuickTemplateArchived(id: String, archived: Bool, expectedUpdatedAt: Int64, at timestamp: Int64) async throws {
        try await write { db in
            guard var row = try QuickTemplateRecord.fetchOne(db, key: id) else { throw QuickTemplateError.unavailable }
            guard row.updated_at_epoch_millis == expectedUpdatedAt else { throw LedgerError.conflict }
            guard (row.is_archived != 0) != archived else { return }
            row.is_archived = archived ? 1 : 0
            row.updated_at_epoch_millis = try Self.templateTimestamp(timestamp, after: row.updated_at_epoch_millis)
            try row.update(db)
        }
    }

    func deleteQuickTemplate(id: String, expectedUpdatedAt: Int64) async throws {
        try await write { db in
            guard let row = try QuickTemplateRecord.fetchOne(db, key: id) else { throw QuickTemplateError.unavailable }
            guard row.updated_at_epoch_millis == expectedUpdatedAt else { throw LedgerError.conflict }
            _ = try row.delete(db)
        }
    }

    func recordQuickTemplateUse(_ transaction: LedgerTransaction, expecting content: QuickTemplateContent) async throws -> LedgerTransaction {
        try transaction.validate()
        guard let templateID = transaction.sourceID, let requestKey = transaction.requestKey,
              QuickTemplateUse.recordsUsage(source: transaction.source, requestKey: requestKey) else { throw LedgerError.conflict }
        return try await write { db in
            if let prior = try Self.find(db, requestKey: requestKey) {
                guard prior.source == .template, prior.sourceID == templateID else { throw LedgerError.conflict }
                return prior
            }
            let template = try Self.requireAvailableTemplate(db, id: templateID)
            guard template.content == content, transaction.type == content.type, transaction.categoryID == content.categoryID,
                  transaction.accountID == content.accountID, transaction.tagIDs == content.tagIDs, transaction.note == content.note,
                  [.identity, .latest].contains(transaction.exchangeRate.method), transaction.crypto == nil, transaction.deletedAt == nil
            else { throw LedgerError.conflict }
            if transaction.exchangeRate.method == .identity {
                let scale = try CurrencyRecord.fetchOne(db, key: transaction.original.currencyCode.rawValue)?.default_scale
                guard Int64(transaction.original.scale) == scale,
                      try transaction.original == content.amount.rescaled(to: transaction.original.scale) else { throw LedgerError.conflict }
            } else {
                guard transaction.original == content.amount else { throw LedgerError.conflict }
            }
            try Self.insertTransaction(db, transaction)
            try Self.changeTemplateUsage(db, transactionID: transaction.id, restoring: true, at: transaction.updatedAt)
            return transaction
        }
    }

    static func requireAvailableTemplate(_ db: Database, id: String) throws -> QuickTemplate {
        guard let row = try QuickTemplateRecord.fetchOne(db, key: id), row.is_archived == 0 else { throw QuickTemplateError.unavailable }
        let template = try row.model(tagIDs: templateTags(db, id: id))
        try validateTemplateReferences(db, content: template.content)
        return template
    }

    private static func templateTags(_ db: Database, id: String) throws -> Set<String> {
        try Set(String.fetchAll(db, sql: "SELECT tag_id FROM quick_template_tags WHERE template_id = ?", arguments: [id]))
    }

    private static func validateTemplateReferences(_ db: Database, content: QuickTemplateContent,
                                                    keeping existing: QuickTemplateRecord? = nil, previousTags: Set<String> = []) throws {
        let code = content.amount.currencyCode.rawValue
        guard let currency = try CurrencyRecord.fetchOne(db, key: code), currency.asset_type == AssetType.fiat.rawValue,
              currency.is_enabled == 1 || existing?.currency_code == code else { throw QuickTemplateError.currencyUnavailable }
        guard let category = try CategoryRecord.fetchOne(db, key: content.categoryID),
              category.transaction_type == content.type.rawValue,
              category.is_archived == 0 || existing?.category_id == category.id else { throw QuickTemplateError.categoryUnavailable }
        guard let account = try AccountRecord.fetchOne(db, key: content.accountID),
              account.is_archived == 0 || existing?.account_id == account.id else { throw QuickTemplateError.accountUnavailable }
        for id in content.tagIDs {
            guard let tag = try TagRecord.fetchOne(db, key: id),
                  tag.is_archived == 0 || previousTags.contains(id) else { throw QuickTemplateError.tagUnavailable }
        }
    }

    /// Called inside the same writer transaction as insert, soft delete or restore.
    static func changeTemplateUsage(_ db: Database, transactionID: String, restoring: Bool, at timestamp: Int64) throws {
        guard let transaction = try TransactionRecord.fetchOne(db, key: transactionID),
              transaction.source_type == TransactionSource.template.rawValue,
              QuickTemplateUse.recordsUsage(source: .template, requestKey: transaction.request_key),
              let id = transaction.source_id, var template = try QuickTemplateRecord.fetchOne(db, key: id) else { return }
        if restoring {
            let newCount = template.usage_count.addingReportingOverflow(1)
            guard !newCount.overflow else { throw QuickTemplateError.usageOverflow }
            template.usage_count = newCount.partialValue
            template.last_used_at = max(template.last_used_at ?? template.created_at_epoch_millis, transaction.created_at_epoch_millis)
        } else {
            guard template.usage_count > 0 else { throw LedgerError.conflict }
            template.usage_count -= 1
            template.last_used_at = try Int64.fetchOne(db, sql: """
                SELECT MAX(created_at_epoch_millis) FROM transactions
                WHERE source_type = 'TEMPLATE' AND source_id = ? AND deleted_at_epoch_millis IS NULL AND request_key GLOB ?
                """, arguments: [id, QuickTemplateUse.requestPrefix + "*"])
        }
        template.updated_at_epoch_millis = try templateTimestamp(timestamp, after: template.updated_at_epoch_millis)
        try template.update(db)
    }

    private static func templateTimestamp(_ timestamp: Int64, after previous: Int64?) throws -> Int64 {
        guard let previous else { return timestamp }
        let next = previous.addingReportingOverflow(1)
        guard !next.overflow else { throw LedgerError.dateOverflow }
        return max(timestamp, next.partialValue)
    }
}

private extension QuickTemplateRecord {
    func model(tagIDs: Set<String>) throws -> QuickTemplate {
        let content = try QuickTemplateContent(name: name, iconKey: icon_key,
            type: storedEnum(transaction_type, as: TransactionType.self),
            amount: Money(minorUnits: amount_minor, currencyCode: CurrencyCode(currency_code), scale: Int(amount_scale)),
            categoryID: category_id, accountID: account_id, note: note, tagIDs: tagIDs)
        return QuickTemplate(id: id, content: content, sortOrder: sort_order, usageCount: usage_count,
            lastUsedAt: last_used_at, isArchived: is_archived != 0, createdAt: created_at_epoch_millis, updatedAt: updated_at_epoch_millis)
    }
}
