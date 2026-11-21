import Foundation

actor PrivateRecordingCoverageStore: RecordingCoverageRepository {
    private let defaults: UserDefaults
    private let key = "recording-coverage-v1"

    init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func load() throws -> RecordingCoverage {
        guard let value = defaults.data(forKey: key) else { return RecordingCoverage() }
        return try JSONDecoder().decode(RecordingCoverage.self, from: value)
    }

    func save(_ coverage: RecordingCoverage) throws {
        try defaults.set(JSONEncoder().encode(coverage), forKey: key)
    }
}
