import GRDB

extension GRDBLedgerRepository {
    func isManagedTransaction(id: String) async throws -> Bool {
        try await read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM account_transfers WHERE profit_transaction_id = ?)", arguments: [id]) ?? false
        }
    }
    func searchTransactions(_ query: LedgerQuery) async throws -> LedgerPage {
        guard (1...200).contains(query.limit), query.text.count <= 500,
              query.startDay == nil || query.endDayExclusive == nil || query.startDay! < query.endDayExclusive! else { throw LedgerError.invalidField("query") }
        return try await read { db in
            var conditions = [query.deletedOnly ? "t.deleted_at_epoch_millis IS NOT NULL" : "t.deleted_at_epoch_millis IS NULL"]
            var args = StatementArguments()
            if let type = query.type { conditions.append("t.transaction_type = ?"); args += [type.rawValue] }
            if let id = query.categoryID { conditions.append("(t.category_id = ? OR t.category_id IN (SELECT id FROM categories WHERE parent_id = ?))"); args += [id, id] }
            if let id = query.accountID { conditions.append("t.account_id = ?"); args += [id] }
            if let id = query.tagID { conditions.append("EXISTS(SELECT 1 FROM transaction_tags tt WHERE tt.transaction_id = t.id AND tt.tag_id = ?)"); args += [id] }
            if let day = query.startDay { conditions.append("t.occurred_local_epoch_day >= ?"); args += [day] }
            if let day = query.endDayExclusive { conditions.append("t.occurred_local_epoch_day < ?"); args += [day] }
            if !query.text.isEmpty {
                conditions.append("(instr(lower(COALESCE(t.note,'')), lower(?)) > 0 OR instr(lower(c.name),lower(?)) > 0 OR instr(lower(a.name),lower(?)) > 0 OR EXISTS(SELECT 1 FROM transaction_tags tt JOIN tags g ON tt.tag_id = g.id WHERE tt.transaction_id = t.id AND instr(lower(g.name), lower(?)) > 0))")
                args += [query.text, query.text, query.text, query.text]
            }
            if let cursor = query.cursor {
                conditions.append("(t.occurred_at_epoch_millis < ? OR (t.occurred_at_epoch_millis = ? AND t.id < ?))")
                args += [cursor.occurredAt, cursor.occurredAt, cursor.id]
            }
            args += [query.limit + 1]
            var rows = try Self.load(db, sql: "SELECT t.* FROM transactions t JOIN categories c ON t.category_id = c.id JOIN accounts a ON t.account_id = a.id WHERE \(conditions.joined(separator: " AND ")) ORDER BY t.occurred_at_epoch_millis DESC, t.id DESC LIMIT ?", arguments: args)
            let more = rows.count > query.limit
            if more { rows.removeLast() }
            let next = more ? rows.last.map { LedgerCursor(occurredAt: $0.occurredAt.epochMillis, id: $0.id) } : nil
            return LedgerPage(rows: rows, next: next)
        }
    }
}
