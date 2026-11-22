import BackgroundTasks
import Foundation
import UserNotifications

@MainActor
final class RecurringSystem {
    static var refreshIdentifier: String { (Bundle.main.bundleIdentifier ?? "com.personal.cost") + ".recurring-refresh" }
    private static let reminderPreference = "recurringRemindersEnabled"
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let isUITesting: Bool
    private var reminderUpdate: Task<Void, Error>?

    init() {
        #if DEBUG
        isUITesting = ProcessInfo.processInfo.arguments.contains("--cost-ui-testing")
        #else
        isUITesting = false
        #endif
    }

    var remindersEnabled: Bool { !isUITesting && defaults.bool(forKey: Self.reminderPreference) }

    func resetLocalData() async {
        guard !isUITesting else { return }
        defaults.removeObject(forKey: Self.reminderPreference)
        reminderUpdate?.cancel()
        _ = await reminderUpdate?.result
        scheduleRefresh(earliest: nil)
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func enableReminders(_ enabled: Bool) async throws -> Bool {
        guard !isUITesting else { return false }
        let allowed = enabled ? try await requestNotificationAuthorization() : false
        defaults.set(allowed, forKey: Self.reminderPreference)
        return allowed
    }

    func scheduleRefresh(earliest: Int64?) {
        #if !targetEnvironment(simulator)
        guard !isUITesting else { return }
        guard let earliest else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = max(Date().addingTimeInterval(15 * 60), Date(timeIntervalSince1970: TimeInterval(earliest) / 1000))
        // Background App Refresh may be disabled or unavailable for this installation.
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    func refreshReminders(for rules: [RecurringRule], now: Int64) async throws {
        guard !isUITesting else { return }
        let prior = reminderUpdate
        let update = Task {
            _ = await prior?.result
            try Task.checkCancellation()
            try await applyReminders(for: rules, now: now)
        }
        reminderUpdate = update
        try await withTaskCancellationHandler { try await update.value } onCancel: { update.cancel() }
    }

    private func applyReminders(for rules: [RecurringRule], now: Int64) async throws {
        let allowed = await authorizationAllowsReminders()
        let desired = remindersEnabled && allowed ? try RecurringReminder.upcoming(rules: rules, after: now, limit: 32) : []
        let previous = await pendingReminderIDs()
        try Task.checkCancellation()
        let wanted = Set(desired.map(\.id))
        center.removePendingNotificationRequests(withIdentifiers: Array(previous.subtracting(wanted)))
        for reminder in desired where !previous.contains(reminder.id) {
            try Task.checkCancellation()
            let date = Date(timeIntervalSince1970: TimeInterval(reminder.instant) / 1000)
            guard date > Date() else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = calendar.dateComponents(in: calendar.timeZone, from: date)
            let triggerDate = DateComponents(calendar: calendar, timeZone: calendar.timeZone,
                year: components.year, month: components.month, day: components.day,
                hour: components.hour, minute: components.minute, second: components.second)
            let content = UNMutableNotificationContent()
            content.title = String(localized: "周期记账提醒")
            content.body = String(localized: "有一笔周期账单到期。打开 Cost 查看处理情况。")
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            try await addNotification(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    // Extract sendable values before crossing from the system callback to the main actor.
    private func requestNotificationAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { @Sendable allowed, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: allowed) }
            }
        }
    }

    private func addNotification(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { @Sendable error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func authorizationAllowsReminders() async -> Bool {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { @Sendable settings in
                let status = settings.authorizationStatus
                continuation.resume(returning: [.authorized, .provisional, .ephemeral].contains(status))
            }
        }
    }

    private func pendingReminderIDs() async -> Set<String> {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { @Sendable requests in
                let ids = requests.map(\.identifier).filter { $0.hasPrefix("cost-reminder:recurring:") }
                continuation.resume(returning: Set(ids))
            }
        }
    }
}
