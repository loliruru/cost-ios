import SwiftUI

@main
@MainActor
struct CostApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            Group {
                if let ledger = container.ledger { LedgerRootView(model: ledger) }
                else { ProgressView("Cost") }
            }
                .environment(container)
                .task { await container.start() }
                .alert("无法打开本地数据", isPresented: $container.startupFailed) {
                    Button("重试") { Task { await container.start() } }
                } message: {
                    Text("已有数据会保留。请重试，不要卸载应用。")
                }
        }
    }
}
