import CommonCrypto
import CryptoKit
import Foundation
import Security

enum BackupEnvelope {
    private static let magic = Data("COSTBK01".utf8)
    private static let saltSize = 16
    private static let nonceSize = 12
    private static let tagSize = 16
    private static let encryptedHeaderSize = 9 + saltSize + nonceSize

    static func encode(_ zip: URL, to destination: URL, password: String) throws {
        guard password.isEmpty || (12...1024).contains(password.utf16.count) else {
            throw PortableDataError.invalidPassword
        }
        let overhead = password.isEmpty ? 9 : encryptedHeaderSize + tagSize
        _ = try PortableFiles.size(zip, limit: PortableLimits.archive - overhead)
        let output = try PortableFiles.openOutput(destination)
        defer { try? output.close() }
        var header = magic
        header.append(password.isEmpty ? 0 : 1)
        if password.isEmpty {
            try output.write(contentsOf: header)
            try PortableFiles.chunks(zip, limit: PortableLimits.archive - overhead) {
                try output.write(contentsOf: $0)
            }
        } else {
            let salt = try random(saltSize)
            let nonce = try AES.GCM.Nonce(data: random(nonceSize))
            header.append(salt)
            header.append(contentsOf: nonce)
            let input = try Data(contentsOf: zip, options: .alwaysMapped)
            let sealed = try AES.GCM.seal(input, using: key(password, salt: salt), nonce: nonce, authenticating: header)
            guard let combined = sealed.combined else { throw PortableDataError.storage }
            try output.write(contentsOf: header)
            try output.write(contentsOf: combined.dropFirst(nonceSize))
        }
        try output.synchronize()
    }

    static func decode(_ source: URL, to zip: URL, password: String) throws {
        guard password.utf16.count <= 1024 else { throw PortableDataError.invalidPassword }
        let size = try PortableFiles.size(source, limit: PortableLimits.archive)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard try PortableFiles.read(input, count: 8) == magic else { throw PortableDataError.invalidFormat }
        let mode = try PortableFiles.read(input, count: 1).first
        switch mode {
        case 0:
            let output = try PortableFiles.openOutput(zip)
            defer { try? output.close() }
            var remaining = size - 9
            while remaining > 0 {
                try Task.checkCancellation()
                let block = try PortableFiles.read(input, count: min(remaining, PortableFiles.chunkSize))
                try output.write(contentsOf: block)
                remaining -= block.count
            }
            try output.synchronize()
        case 1:
            guard !password.isEmpty else { throw PortableDataError.passwordRequired }
            guard size > encryptedHeaderSize + tagSize else { throw PortableDataError.authenticationFailed }
            let data = try Data(contentsOf: source, options: .alwaysMapped)
            let header = data.prefix(encryptedHeaderSize)
            let salt = header[9..<(9 + saltSize)]
            let plaintext: Data
            do {
                // CryptoKit's combined representation starts at the envelope nonce.
                let box = try AES.GCM.SealedBox(combined: data.dropFirst(9 + saltSize))
                plaintext = try AES.GCM.open(box, using: key(password, salt: salt), authenticating: header)
            } catch { throw PortableDataError.authenticationFailed }
            try Task.checkCancellation()
            try plaintext.write(to: zip, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        default: throw PortableDataError.invalidFormat
        }
    }

    static func key(_ password: String, salt: Data) throws -> SymmetricKey {
        var bytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        defer {
            _ = bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            _ = derived.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        }
        let byteCount = bytes.count
        let keySize = derived.count
        let status = bytes.withUnsafeBytes { secret in
            salt.withUnsafeBytes { saltBuffer in
                derived.withUnsafeMutableBufferPointer { result in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        secret.bindMemory(to: CChar.self).baseAddress, byteCount,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, result.baseAddress, keySize)
                }
            }
        }
        guard status == kCCSuccess else { throw PortableDataError.storage }
        return SymmetricKey(data: derived)
    }

    private static func random(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw PortableDataError.storage }
        return bytes
    }
}
