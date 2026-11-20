import SwiftUI

@main
@MainActor
struct CostApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var container = AppContainer(recurringEnvironment: Self.recurringEnvironment())

    var body: some Scene {
        let appContainer = container
        WindowGroup {
            Group {
                if let ledger = container.ledger, let recurring = container.recurring, let statistics = container.statistics {
                    LedgerRootView(model: ledger, recurring: recurring, statistics: statistics)
                }
                else { ProgressView("Cost") }
            }
                .environment(container)
                .task(id: scenePhase) {
                    if scenePhase == .active {
                        container.statistics?.refreshDay()
                        await container.processRecurring()
                    }
                }
                .alert("无法打开本地数据", isPresented: $container.startupFailed) {
                    Button("重试") { Task { await container.processRecurring() } }
                } message: {
                    Text("已有数据会保留。请重试，不要卸载应用。")
                }
        }
        .backgroundTask(.appRefresh(RecurringSystem.refreshIdentifier)) {
            await appContainer.processRecurring(background: true)
        }
    }

    private static func recurringEnvironment() -> LedgerEnvironment {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--cost-ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--cost-recurring-fixed-clock") {
            return LedgerEnvironment(now: { 1_797_249_600_000 }, zoneID: { "UTC" })
        }
        #endif
        return LedgerEnvironment()
    }
}
