import Foundation
import Testing
@testable import Cost

struct FoundationTests {
    /// A hosted test also checks that the application loads with the intended identity.
    @Test @MainActor
    func applicationHostLoads() {
        _ = AppContainer()
        #expect(Bundle.main.bundleIdentifier == "com.personal.cost")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "0.1.0")
    }
}
