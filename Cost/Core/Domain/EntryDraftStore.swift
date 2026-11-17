import Foundation

protocol EntryDraftStore: Sendable {
    func load(key: String) async throws -> EntryDraft?
    func save(_ draft: EntryDraft, key: String) async throws
    func remove(key: String) async
}
