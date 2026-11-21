import Foundation

actor PrivateBaseCurrencyPreferences: BaseCurrencyPreferences {
    private let defaults: UserDefaults
    private let key = "cost.baseCurrencyCode"

    init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func baseCurrencyCode() -> String {
        defaults.string(forKey: key) ?? EntryDraft.defaultBaseCurrencyCode
    }

    func setBaseCurrencyCode(_ code: String) {
        defaults.set(code, forKey: key)
    }
}
