import CoreFoundation
import Foundation

struct PortableSettings: Codable, Sendable {
    var base_currency_code: String?
    var theme_mode: String?
    var glass_quality: String?
    var anomaly_sensitivity: String?
    var dynamic_color_enabled: Bool?
    var reduce_motion_enabled: Bool?
    var anomaly_enabled: Bool?

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= PortableLimits.settings,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PortableDataError.invalidFormat
        }
        let strings = ["base_currency_code", "theme_mode", "glass_quality", "anomaly_sensitivity"]
        let booleans = ["dynamic_color_enabled", "reduce_motion_enabled", "anomaly_enabled"]
        for (key, value) in object {
            if strings.contains(key), value is String { continue }
            if booleans.contains(key), let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { continue }
            throw PortableDataError.invalidFormat
        }
        let settings = try JSONDecoder().decode(Self.self, from: data)
        if let code = settings.base_currency_code { _ = try CurrencyCode(code) }
        if let theme = settings.theme_mode, !["SYSTEM", "LIGHT", "DARK"].contains(theme) {
            throw PortableDataError.invalidFormat
        }
        if let quality = settings.glass_quality, !["AUTO", "HIGH", "MEDIUM", "LOW"].contains(quality) {
            throw PortableDataError.invalidFormat
        }
        if let sensitivity = settings.anomaly_sensitivity, AnomalySensitivity(rawValue: sensitivity) == nil {
            throw PortableDataError.invalidFormat
        }
        return settings
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

actor PortableSettingsStore: BaseCurrencyPreferences, AnomalyPreferencesRepository {
    private let file: URL
    private var settings: PortableSettings

    init(root: URL, suiteName: String? = nil) throws {
        let file = root.appendingPathComponent("portable-settings.json")
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try PortableFiles.size(file, limit: PortableLimits.settings)
            settings = try PortableSettings.decode(Data(contentsOf: file))
        } else {
            let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
            settings = PortableSettings(base_currency_code: defaults.string(forKey: "cost.baseCurrencyCode"),
                anomaly_sensitivity: defaults.string(forKey: "anomaly_sensitivity"),
                anomaly_enabled: defaults.object(forKey: "anomaly_enabled") as? Bool)
        }
    }

    func snapshot() -> PortableSettings { settings }

    func reset() throws {
        try PortableFiles.removeIfPresent(file)
        settings = PortableSettings()
    }

    func replace(_ settings: PortableSettings) throws {
        try PortableFiles.directory(file.deletingLastPathComponent())
        try settings.encoded().write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.synchronize()
        self.settings = settings
    }

    func baseCurrencyCode() -> String { settings.base_currency_code ?? EntryDraft.defaultBaseCurrencyCode }

    func setBaseCurrencyCode(_ code: String) throws {
        var updated = settings
        updated.base_currency_code = code
        try replace(updated)
    }

    func load() -> AnomalyPreferences {
        AnomalyPreferences(enabled: settings.anomaly_enabled ?? true,
            sensitivity: settings.anomaly_sensitivity.flatMap(AnomalySensitivity.init(rawValue:)) ?? .normal)
    }

    func save(_ preferences: AnomalyPreferences) throws {
        var updated = settings
        updated.anomaly_enabled = preferences.enabled
        updated.anomaly_sensitivity = preferences.sensitivity.rawValue
        try replace(updated)
    }
}
