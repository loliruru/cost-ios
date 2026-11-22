import Foundation

/// A bounded private draft, separate from the ledger. Never contains credentials.
actor PrivateEntryDraftStore: EntryDraftStore {
    private static let legacyManualKey = "entry-draft-v1-new"
    private let defaults: UserDefaults
    init(suiteName: String? = nil) { defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    func load(key: EntryDraftKey) throws -> EntryDraft? {
        if let draft = try read(storageKey(key)) { return draft }
        guard case .manual(let base) = key,
              let legacy = try read(Self.legacyManualKey),
              legacy.baseCurrencyCode == base, legacy.sourceTemplateID == nil, legacy.editingUpdatedAt == nil else {
            return nil
        }
        try save(legacy, key: key)
        defaults.removeObject(forKey: Self.legacyManualKey)
        return legacy
    }

    private func read(_ key: String) throws -> EntryDraft? {
        guard let data = defaults.data(forKey: key), data.count <= 65536 else { return nil }
        return try JSONDecoder().decode(EntryDraft.self, from: data)
    }

    func save(_ draft: EntryDraft, key: EntryDraftKey) throws {
        let data = try JSONEncoder().encode(draft)
        guard data.count <= 65536 else { throw LedgerError.invalidField("draftTooLarge") }
        defaults.set(data, forKey: storageKey(key))
    }

    func remove(key: EntryDraftKey) {
        defaults.removeObject(forKey: storageKey(key))
    }

    private func storageKey(_ key: EntryDraftKey) -> String {
        switch key {
        case .manual(let base): "entry-manual-draft-v1-\(base)"
        case .template(let id): "entry-draft-v1-template:\(id)"
        case .transaction(let id): "entry-draft-v1-\(id)"
        }
    }
}
