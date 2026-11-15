import SwiftUI

@main
@MainActor
struct CostApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            Color.clear
                .environment(container)
        }
    }
}
