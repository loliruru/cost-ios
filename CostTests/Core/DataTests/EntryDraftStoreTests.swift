import Foundation
import Testing
@testable import Cost

struct EntryDraftStoreTests {
    @Test func privateDraftSurvivesStoreRecreationAndClearsAfterSave() async throws {
        let suite = "cost-draft-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let first = PrivateEntryDraftStore(suiteName: suite)
        var draft = EntryDraft(id: "stable-id", requestKey: "stable-request", occurredMillis: 2000, zoneID: "Asia/Singapore")
        draft.amount = "12.34"; draft.note = "中文草稿"; draft.tagIDs = ["a", "b"]
        try await first.save(draft, key: "new")
        let reopened = PrivateEntryDraftStore(suiteName: suite)
        #expect(try await reopened.load(key: "new") == draft)
        await reopened.remove(key: "new")
        #expect(try await first.load(key: "new") == nil)
        draft.note = String(repeating: "界", count: 65536)
        await #expect(throws: (any Error).self) { try await first.save(draft, key: "new") }
        #expect(try await reopened.load(key: "new") == nil)
    }
}
