import Foundation

/// A bounded private draft, separate from the ledger. Never contains credentials.
actor PrivateEntryDraftStore: EntryDraftStore {
    private let defaults: UserDefaults
    init(suiteName: String? = nil) { defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }
    func load(key: String) throws -> EntryDraft? {
        guard let data = defaults.data(forKey: "entry-draft-v1-\(key)"), data.count <= 65536 else { return nil }
        return try JSONDecoder().decode(EntryDraft.self, from: data)
    }
    func save(_ draft: EntryDraft, key: String) throws {
        let data = try JSONEncoder().encode(draft)
        guard data.count <= 65536 else { throw LedgerError.invalidField("draftTooLarge") }
        defaults.set(data, forKey: "entry-draft-v1-\(key)")
    }
    func remove(key: String) { defaults.removeObject(forKey: "entry-draft-v1-\(key)") }
}
