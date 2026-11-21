import Foundation
import Security

actor KeychainQuoteCredentials: QuoteCredentials {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "cost") + ".quotes",
         kSecAttrAccount as String: "twelve-data",
         kSecAttrSynchronizable as String: false]
    }

    func apiKey() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw QuoteFailure.credentialsUnavailable }
        return key
    }

    func setAPIKey(_ key: String?) throws {
        if let key {
            guard (1...256).contains(key.utf8.count), key.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw QuoteFailure.invalidRequest
            }
            let data = Data(key.utf8)
            let attributes = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecSuccess { return }
            guard status == errSecItemNotFound else { throw QuoteFailure.credentialsUnavailable }
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw QuoteFailure.credentialsUnavailable }
        } else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw QuoteFailure.credentialsUnavailable }
        }
    }
}
