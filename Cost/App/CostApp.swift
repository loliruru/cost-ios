import SwiftUI

@main
@MainActor
struct CostApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            Text("Cost")
                .environment(container)
        }
    }
}
