import Foundation

struct RecurringContent: Equatable, Sendable {
    var name: String
    var type: TransactionType
    var amount: Money
    var categoryID: String
    var accountID: String
    var note: String?
    var tagIDs: Set<String>
    var schedule: RecurringSchedule
    var catchUp: RecurringCatchUp
}

struct RecurringRule: Equatable, Identifiable, Sendable {
    let id: String
    let content: RecurringContent
    let isEnabled: Bool
    let nextOccurrence: Int64?
    let version: Int64
    let createdAt: Int64
}

struct RecurringDraft: Sendable {
    var name = ""
    var type = TransactionType.expense
    var amount = ""
    var currencyCode = EntryDraft.defaultBaseCurrencyCode
    var categoryID = ""
    var accountID = ""
    var note = ""
    var tagIDs: Set<String> = []
    var schedule: RecurringSchedule
    var catchUp = RecurringCatchUp.createMissed

    init(schedule: RecurringSchedule, existing: RecurringRule? = nil) {
        self.schedule = schedule
        guard let content = existing?.content else { return }
        name = content.name
        type = content.type
        amount = content.amount.plainText
        currencyCode = content.amount.currencyCode.rawValue
        categoryID = content.categoryID
        accountID = content.accountID
        note = content.note ?? ""
        tagIDs = content.tagIDs
        catchUp = content.catchUp
    }
}

enum RecurringStatus: String, Sendable {
    case pending = "PENDING", created = "CREATED", skipped = "SKIPPED"
    case retryable = "FAILED_RETRYABLE", failed = "FAILED_FINAL"

    var needsAttention: Bool { self == .retryable || self == .failed }
    var isHandled: Bool { self == .created || self == .skipped }
}

enum RecurringIssue: String, Error, Sendable {
    case referenceUnavailable = "REFERENCE_UNAVAILABLE", currencyUnavailable = "CURRENCY_UNAVAILABLE"
    case valuationUnavailable = "FX_NOT_CONFIGURED", staleQuote = "FX_CONFIRMATION_REQUIRED"
    case conversionFailed = "RATE_CONVERSION_FAILED"
}

struct RecurringExecution: Equatable, Identifiable, Sendable {
    let id: String
    let ruleID: String
    let scheduledAt: Int64
    let status: RecurringStatus
    let transactionID: String?
    let attempts: Int64
    let issue: RecurringIssue?
}

enum RecurringOutcome: Sendable {
    case ready(LedgerTransaction), skip, failure(RecurringIssue, retryable: Bool)
}

struct RecurringWork: Sendable {
    let rule: RecurringRule
    let scheduledAt: Int64
    let execution: RecurringExecution?

    static func requestKey(ruleID: String, instant: Int64) -> String { "recurring:\(ruleID):\(instant)" }
    var requestKey: String { Self.requestKey(ruleID: rule.id, instant: scheduledAt) }
}

protocol RecurringRepository: Sendable {
    func recurringRules() async throws -> [RecurringRule]
    func saveRecurringRule(id: String, content: RecurringContent, expectedVersion: Int64?, at: Int64) async throws
    func setRecurringEnabled(_ rule: RecurringRule, enabled: Bool, catchUp: RecurringCatchUp, at: Int64) async throws
    func deleteRecurringRule(_ rule: RecurringRule) async throws
    func recurringFailures(limit: Int, after: RecurringExecution?) async throws -> [RecurringExecution]
    func dueRecurringWork(at: Int64, excluding: Set<String>) async throws -> RecurringWork?
    func recurringWork(for execution: RecurringExecution) async throws -> RecurringWork?
    func commitRecurringWork(_ work: RecurringWork, outcome: RecurringOutcome, at: Int64, isManual: Bool) async throws -> RecurringStatus?
}

struct ManageRecurringRules: Sendable {
    let rules: any RecurringRepository
    let currencies: any CurrencyRepository
    var environment = LedgerEnvironment()

    func save(_ draft: RecurringDraft, editing rule: RecurringRule?) async throws {
        let name = draft.name.precomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty, name.count <= 120, draft.amount.count <= 96, draft.note.count <= 8192,
              draft.tagIDs.count <= 100 else { throw LedgerError.invalidField("recurringInput") }
        try draft.schedule.validate()
        let code = try CurrencyCode(draft.currencyCode)
        guard let currency = try await currencies.currency(code: code), currency.assetType == .fiat,
              currency.isEnabled || rule?.content.amount.currencyCode == code else { throw RecurringIssue.currencyUnavailable }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = RecurringContent(name: name, type: draft.type,
            amount: try Money.parse(draft.amount, currencyCode: code, scale: currency.defaultScale),
            categoryID: draft.categoryID, accountID: draft.accountID, note: note.isEmpty ? nil : note,
            tagIDs: draft.tagIDs, schedule: draft.schedule, catchUp: draft.catchUp)
        try await rules.saveRecurringRule(id: rule?.id ?? environment.newID(), content: content,
            expectedVersion: rule?.version, at: environment.now())
    }

    func setEnabled(_ rule: RecurringRule, enabled: Bool, catchUp: RecurringCatchUp) async throws {
        try await rules.setRecurringEnabled(rule, enabled: enabled, catchUp: catchUp, at: environment.now())
    }
}

protocol RecurringFiatProvider: Sendable {
    func latest(original: CurrencyCode, base: CurrencyCode) async throws -> FiatQuote
    func historical(original: CurrencyCode, base: CurrencyCode, epochDay: Int64) async throws -> FiatQuote
}

struct UnconfiguredRecurringFiatProvider: RecurringFiatProvider {
    func latest(original: CurrencyCode, base: CurrencyCode) async throws -> FiatQuote { throw RecurringIssue.valuationUnavailable }
    func historical(original: CurrencyCode, base: CurrencyCode, epochDay: Int64) async throws -> FiatQuote { throw RecurringIssue.valuationUnavailable }
}

struct ProcessRecurringRules: Sendable {
    let rules: any RecurringRepository
    let currencies: any CurrencyRepository
    var provider: any RecurringFiatProvider = UnconfiguredRecurringFiatProvider()
    var environment = LedgerEnvironment()

    /// Bounded per invocation for background refresh. Foreground callers can drain further batches.
    func runDue(limit: Int = 100, excluding blocked: inout Set<String>) async throws -> Bool {
        for _ in 0..<limit {
            try Task.checkCancellation()
            let now = environment.now()
            guard let work = try await rules.dueRecurringWork(at: now, excluding: blocked) else { return false }
            let schedule = work.rule.content.schedule
            let missed = try schedule.localDay(at: work.scheduledAt) < schedule.localDay(at: now)
            let outcome: RecurringOutcome
            if work.execution?.status.isHandled == true || work.execution?.status == .failed ||
                (missed && work.rule.content.catchUp == .skipMissed) {
                outcome = .skip
            } else {
                outcome = try await prepare(work, now: now, historical: missed)
            }
            try Task.checkCancellation()
            if try await rules.commitRecurringWork(work, outcome: outcome, at: now, isManual: false) == .retryable {
                blocked.insert(work.rule.id)
            }
        }
        return true
    }

    func resolve(_ execution: RecurringExecution, skipping: Bool) async throws -> RecurringStatus? {
        guard let work = try await rules.recurringWork(for: execution) else { throw LedgerError.conflict }
        let now = environment.now()
        let schedule = work.rule.content.schedule
        guard skipping || (work.rule.isEnabled && work.scheduledAt <= now) else { throw LedgerError.conflict }
        let historical = try schedule.localDay(at: work.scheduledAt) < schedule.localDay(at: now)
        let outcome = skipping ? .skip : try await prepare(work, now: now, historical: historical)
        try Task.checkCancellation()
        return try await rules.commitRecurringWork(work, outcome: outcome, at: now, isManual: true)
    }

    private func prepare(_ work: RecurringWork, now: Int64, historical: Bool) async throws -> RecurringOutcome {
        let content = work.rule.content
        let baseCode = try CurrencyCode(EntryDraft.defaultBaseCurrencyCode)
        guard let originalCurrency = try await currencies.currency(code: content.amount.currencyCode),
              let base = try await currencies.currency(code: baseCode),
              originalCurrency.isEnabled, base.isEnabled, originalCurrency.assetType == .fiat, base.assetType == .fiat else {
            return .failure(.currencyUnavailable, retryable: false)
        }
        let occurred = try OccurredAt(epochMillis: work.scheduledAt, zoneID: content.schedule.zoneID)
        do {
            let original: Money
            let converted: Money
            let rate: ExchangeRateSnapshot
            if originalCurrency.code == base.code {
                original = try content.amount.rescaled(to: base.defaultScale)
                converted = original
                rate = try .identity()
            } else {
                original = content.amount
                let quote: FiatQuote
                do {
                    if historical {
                        quote = try await provider.historical(original: original.currencyCode, base: base.code, epochDay: occurred.localEpochDay)
                    } else {
                        quote = try await provider.latest(original: original.currencyCode, base: base.code)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch let issue as RecurringIssue { return .failure(issue, retryable: true) }
                catch { return .failure(.valuationUnavailable, retryable: true) }
                try quote.validate()
                guard quote.original == original.currencyCode, quote.base == base.code,
                      historical ? quote.kind == .historical && quote.rateEpochDay == occurred.localEpochDay :
                          quote.kind == .latest && quote.dataTimestamp <= now && now < quote.expiresAt && now - quote.dataTimestamp < 300_000
                else { return .failure(.staleQuote, retryable: true) }
                converted = try quote.rate.convert(original, to: base.code, scale: base.defaultScale)
                rate = ExchangeRateSnapshot(rate: quote.rate, providerID: quote.providerID, dataTimestamp: quote.dataTimestamp,
                    fetchedAt: quote.fetchedAt, method: historical ? .historical : .latest)
            }
            let recordedAt = max(now, work.rule.createdAt)
            return .ready(try LedgerTransaction(id: environment.newID(), type: content.type, original: original,
                convertedBase: converted, exchangeRate: rate, categoryID: content.categoryID, accountID: content.accountID,
                occurredAt: occurred, note: content.note, source: .recurring, sourceID: work.rule.id, requestKey: work.requestKey,
                createdAt: recordedAt, updatedAt: recordedAt, tagIDs: content.tagIDs))
        } catch is CancellationError { throw CancellationError() }
        catch { return .failure(.conversionFailed, retryable: false) }
    }
}

struct RecurringReminder: Equatable, Sendable {
    let ruleID: String
    let instant: Int64

    var id: String { "cost-reminder:" + RecurringWork.requestKey(ruleID: ruleID, instant: instant) }

    static func upcoming(rules: [RecurringRule], after now: Int64, limit: Int) throws -> [Self] {
        var upcoming: [(rule: RecurringRule, instant: Int64)] = []
        for rule in rules where rule.isEnabled && rule.nextOccurrence != nil {
            let schedule = rule.content.schedule
            let today = try schedule.localDay(at: now)
            guard var instant = try schedule.occurrence(onOrAfter: today) else { continue }
            if instant <= now {
                guard let next = try schedule.next(after: instant) else { continue }
                instant = next
            }
            upcoming.append((rule, instant))
        }
        var reminders: [Self] = []
        while reminders.count < limit, let index = upcoming.indices.min(by: {
            (upcoming[$0].instant, upcoming[$0].rule.id) < (upcoming[$1].instant, upcoming[$1].rule.id)
        }) {
            let candidate = upcoming[index]
            reminders.append(Self(ruleID: candidate.rule.id, instant: candidate.instant))
            if let next = try candidate.rule.content.schedule.next(after: candidate.instant) { upcoming[index].instant = next }
            else { upcoming.remove(at: index) }
        }
        return reminders
    }
}
