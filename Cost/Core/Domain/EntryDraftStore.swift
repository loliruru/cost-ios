import Foundation

enum EntryDraftKey: Hashable, Sendable {
    case manual(baseCurrencyCode: String)
    case template(String)
    case transaction(String)
}

protocol EntryDraftStore: Sendable {
    func load(key: EntryDraftKey) async throws -> EntryDraft?
    func save(_ draft: EntryDraft, key: EntryDraftKey) async throws
    func remove(key: EntryDraftKey) async
}
