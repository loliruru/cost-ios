import Foundation
import Testing
@testable import Cost

struct EntryDraftStoreTests {
    @Test func privateDraftSurvivesStoreRecreationAndClearsAfterSave() async throws {
        let suite = "cost-draft-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let first = PrivateEntryDraftStore(suiteName: suite)
        let key = EntryDraftKey.manual(baseCurrencyCode: "CNY")
        var draft = EntryDraft(id: "stable-id", requestKey: "stable-request", occurredMillis: 2000, zoneID: "Asia/Singapore")
        draft.amount = "12.34"; draft.note = "中文草稿"; draft.tagIDs = ["a", "b"]
        try await first.save(draft, key: key)
        let reopened = PrivateEntryDraftStore(suiteName: suite)
        #expect(try await reopened.load(key: key) == draft)
        await reopened.remove(key: key)
        #expect(try await first.load(key: key) == nil)
        draft.note = String(repeating: "界", count: 65536)
        await #expect(throws: (any Error).self) { try await first.save(draft, key: key) }
        #expect(try await reopened.load(key: key) == nil)
    }

    @Test func migratesLegacyDraftOnlyUnderItsOriginalBaseCurrency() async throws {
        let suite = "cost-draft-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        var legacy = EntryDraft(id: "legacy-usd", requestKey: "legacy-request", occurredMillis: 2000, zoneID: "Asia/Singapore")
        legacy.currencyCode = "USD"
        legacy.baseCurrencyCode = "USD"
        legacy.amount = "15"
        defaults.set(try JSONEncoder().encode(legacy), forKey: "entry-draft-v1-new")
        let store = PrivateEntryDraftStore(suiteName: suite)

        let yuanKey = EntryDraftKey.manual(baseCurrencyCode: "CNY")
        let dollarKey = EntryDraftKey.manual(baseCurrencyCode: "USD")
        #expect(try await store.load(key: yuanKey) == nil)
        let yuan = EntryDraft(id: "new-cny", requestKey: "new-request", occurredMillis: 3000, zoneID: "Asia/Singapore")
        try await store.save(yuan, key: yuanKey)
        let reopened = PrivateEntryDraftStore(suiteName: suite)
        #expect(try await reopened.load(key: dollarKey) == legacy)
        #expect(try await reopened.load(key: yuanKey) == yuan)
        await reopened.remove(key: dollarKey)
        #expect(try await store.load(key: dollarKey) == nil)
    }
}
