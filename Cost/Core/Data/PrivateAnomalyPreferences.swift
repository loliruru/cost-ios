import Foundation

actor PrivateAnomalyPreferences: AnomalyPreferencesRepository {
    private let defaults: UserDefaults

    init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func load() -> AnomalyPreferences {
        let enabled = defaults.object(forKey: "anomaly_enabled") as? Bool ?? true
        let sensitivity = defaults.string(forKey: "anomaly_sensitivity").flatMap(AnomalySensitivity.init(rawValue:)) ?? .normal
        return AnomalyPreferences(enabled: enabled, sensitivity: sensitivity)
    }

    func save(_ preferences: AnomalyPreferences) {
        defaults.set(preferences.enabled, forKey: "anomaly_enabled")
        defaults.set(preferences.sensitivity.rawValue, forKey: "anomaly_sensitivity")
    }
}
