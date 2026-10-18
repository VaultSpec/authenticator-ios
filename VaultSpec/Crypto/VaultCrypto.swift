import CommonCrypto
import CryptoKit
import Foundation

/// Encryption for the vault: AES-256-GCM, with keys derived from the vault password by
/// PBKDF2-HMAC-SHA256.
nonisolated enum VaultCrypto {
    static let pbkdf2Rounds: UInt32 = 600_000

    enum CryptoError: Error { case keyDerivationFailed }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// Slow on purpose: call off the main thread.
    static func deriveKey(password: String, salt: Data, rounds: UInt32 = pbkdf2Rounds) throws -> SymmetricKey {
        let passwordData = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordData.map { Int8(bitPattern: $0) }, passwordData.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }

    /// nonce | ciphertext | tag
    static func seal(_ plaintext: Data, with key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw CryptoError.keyDerivationFailed
        }
        return combined
    }

    /// Throws if the key is wrong or the data was tampered with.
    static func open(_ combined: Data, with key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key)
    }
}
