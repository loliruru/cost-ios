import Foundation

enum PortableDataKind: Sendable {
    case csv, backup

    var fileName: String { self == .csv ? "Cost.csv" : "Cost.costbackup" }
}

enum PortableDataError: Error, Equatable {
    case invalidFormat, unsupportedSchema, tooLarge, invalidPassword, passwordRequired
    case authenticationFailed, conflictingRecords, invalidImage, expiredPreview, storage
}

struct PortableDataPreview: Sendable {
    let token: UUID
    let kind: PortableDataKind
    let transactions: Int
    let images: Int
}

struct PortableDataOutcome: Sendable {
    let imported: Int
    let skipped: Int
    let settingsPending: Bool
}

enum LocalDataResetOutcome: Sendable {
    case complete, cleanupPending
}

protocol PortableDataRepository: Sendable {
    func export(_ kind: PortableDataKind, password: String) async throws -> URL
    func prepare(_ source: URL, kind: PortableDataKind, password: String) async throws -> PortableDataPreview
    func confirm(_ token: UUID) async throws -> PortableDataOutcome
    func discard(_ token: UUID) async
    func discardExport(_ file: URL) async
    func resetLocalData() async throws -> LocalDataResetOutcome
}

/// Serializes recurring evaluation with backup restoration and local resets.
actor LedgerMaintenance {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withAccess<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        if busy { await withCheckedContinuation { waiters.append($0) } }
        else { busy = true }
        defer {
            if waiters.isEmpty { busy = false }
            else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        return try await work()
    }
}
