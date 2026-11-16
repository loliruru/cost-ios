import Foundation
import Testing
@testable import Cost

struct FoundationTests {
    /// A hosted test also checks that the application loads with the intended identity.
    @Test @MainActor
    func applicationHostLoads() throws {
        _ = AppContainer()
        #expect(Bundle.main.bundleIdentifier == "com.personal.cost")
        let version = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        #expect(version.split(separator: ".").count == 3)
    }
}
