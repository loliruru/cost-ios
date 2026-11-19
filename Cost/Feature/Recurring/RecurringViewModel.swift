import Foundation
import Observation

@MainActor @Observable
final class RecurringViewModel {
    let ledger: LedgerViewModel
    private let rules: any RecurringRepository
    private let manage: ManageRecurringRules
    private let processor: ProcessRecurringRules
    private let system: RecurringSystem
    @ObservationIgnored private var reloadGeneration = 0
    @ObservationIgnored private var schedulingGeneration = 0
    private let failurePageSize = 50

    private(set) var rows: [RecurringRule] = []
    private(set) var failures: [RecurringExecution] = []
    private(set) var hasMoreFailures = false
    private(set) var remindersEnabled: Bool
    private(set) var isBusy = false
    var error: String?

    init(ledger: LedgerViewModel, rules: any RecurringRepository, system: RecurringSystem,
         environment: LedgerEnvironment = LedgerEnvironment()) {
        self.ledger = ledger
        self.rules = rules
        self.system = system
        remindersEnabled = system.remindersEnabled
        manage = ManageRecurringRules(rules: rules, currencies: ledger.services.currencies, environment: environment)
        processor = ProcessRecurringRules(rules: rules, currencies: ledger.services.currencies, environment: environment)
    }

    func draft(for rule: RecurringRule?) -> RecurringDraft {
        let environment = manage.environment
        let zone = environment.zoneID()
        let today = (try? OccurredAt(epochMillis: environment.now(), zoneID: zone).localEpochDay) ?? 0
        let schedule = rule?.content.schedule ?? RecurringSchedule(startDay: today, minutes: 540, zoneID: zone,
            intervalUnit: .day, weekdaysMask: 1, dayOfMonth: 1, monthOfYear: 1)
        var draft = RecurringDraft(schedule: schedule, existing: rule)
        if rule == nil {
            draft.categoryID = categories(for: draft).first?.id ?? ""
            let available = ledger.accounts.filter { !$0.isArchived }
            draft.accountID = (available.first(where: \.isDefault) ?? available.first)?.id ?? ""
        }
        return draft
    }

    func categories(for draft: RecurringDraft, keeping id: String? = nil) -> [Category] {
        ledger.categories.filter { $0.type == draft.type && (!$0.isArchived || $0.id == id) }
    }

    func reload() async {
        reloadGeneration += 1
        let token = reloadGeneration
        do {
            async let newRows = rules.recurringRules()
            async let newFailures = rules.recurringFailures(limit: failurePageSize, after: nil)
            let result = try await (newRows, newFailures)
            guard token == reloadGeneration, !Task.isCancelled else { return }
            rows = result.0
            failures = result.1
            hasMoreFailures = result.1.count == failurePageSize
        } catch is CancellationError {} catch { if token == reloadGeneration { self.error = message(for: error) } }
    }

    func loadMoreFailures() async {
        guard let last = failures.last, hasMoreFailures, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let token = reloadGeneration
        do {
            let page = try await rules.recurringFailures(limit: failurePageSize, after: last)
            guard token == reloadGeneration else { return }
            failures += page
            hasMoreFailures = page.count == failurePageSize
        } catch { self.error = message(for: error) }
    }

    func save(_ draft: RecurringDraft, editing rule: RecurringRule?) async -> Bool {
        await change { try await manage.save(draft, editing: rule) }
    }

    func setEnabled(_ rule: RecurringRule, enabled: Bool, catchUp: RecurringCatchUp) async -> Bool {
        await change { try await manage.setEnabled(rule, enabled: enabled, catchUp: catchUp) }
    }

    func delete(_ rule: RecurringRule) async -> Bool {
        await change { try await rules.deleteRecurringRule(rule) }
    }

    func resolve(_ execution: RecurringExecution, skipping: Bool) async {
        var status: RecurringStatus?
        let changed = await change(process: false) {
            status = try await processor.resolve(execution, skipping: skipping)
            guard status != nil else { throw LedgerError.conflict }
        }
        if changed && status != .retryable { await run() }
    }

    func setReminders(_ enabled: Bool) async {
        _ = await change(process: false) {
            remindersEnabled = try await system.enableReminders(enabled)
            if enabled && !remindersEnabled { error = "请在 iOS 设置中允许 Cost 的通知。" }
        }
    }

    func run(background: Bool = false) async {
        var blocked: Set<String> = []
        do {
            repeat {
                let more = try await processor.runDue(excluding: &blocked)
                if !more || background { break }
                await Task.yield()
            } while !Task.isCancelled
        } catch is CancellationError {} catch { if !background { self.error = message(for: error) } }
        guard !Task.isCancelled else { return }
        await refreshSchedules()
        if !background {
            await reload()
            await ledger.reload()
        }
    }

    func rearmBackgroundRefresh() {
        system.scheduleRefresh(earliest: manage.environment.now())
    }

    private func change(process: Bool = true, _ mutation: () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do { try await mutation() }
        catch {
            self.error = message(for: error)
            await reload()
            return false
        }
        if process { await run() }
        else { await reload(); await refreshSchedules() }
        return true
    }

    private func refreshSchedules() async {
        schedulingGeneration += 1
        let token = schedulingGeneration
        do {
            let snapshot = try await rules.recurringRules()
            guard token == schedulingGeneration, !Task.isCancelled else { return }
            system.scheduleRefresh(earliest: snapshot.filter(\.isEnabled).compactMap(\.nextOccurrence).min())
            try await system.refreshReminders(for: snapshot, now: manage.environment.now())
        } catch is CancellationError {} catch { self.error = message(for: error) }
    }

    func message(for error: Error) -> String {
        switch error as? RecurringIssue {
        case .referenceUnavailable: return "分类、账户或标签已停用或不可用，请检查规则。"
        case .currencyUnavailable: return "请选择已启用的法币。"
        case .valuationUnavailable: return "等待外币估值。获得汇率后可重试，也可跳过本次。"
        case .staleQuote: return "暂无符合日期和时效要求的汇率。"
        case .conversionFailed: return "金额或换算结果超出可保存的精度或范围。"
        case nil: break
        }
        switch error as? LedgerError {
        case .invalidTimeZone: return "请选择有效的时区。"
        case .invalidField("recurringSchedule"): return "请检查频率、日期范围和间隔。指定星期时至少选择一天。"
        case .invalidField("recurringInput"): return "请填写规则名称和金额，并检查输入长度。"
        default: return LedgerMessage.text(error)
        }
    }
}
