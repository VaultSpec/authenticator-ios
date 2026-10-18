import Foundation
import LocalAuthentication
import Security

/// Small wrapper over the iOS Keychain for the vault's key material.
nonisolated enum Keychain {
    enum Item: String {
        /// The master key wrapped with the password-derived key.
        case passwordSlot = "vault.password-slot"
        /// The master key itself, readable only after Face ID / Touch ID.
        case biometricKey = "vault.biometric-key"
        /// VaultSpec Cloud session tokens.
        case cloudSession = "cloud.session"
        /// The key cloud backups are encrypted with (derived from the vault password) and its salt.
        case cloudKey = "cloud.backup-key"
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .cancelled: "Authentication was cancelled."
            case .status(let status): SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
            }
        }
    }

    private static let service = "com.vaultspec.authenticator"

    private static func baseQuery(_ item: Item) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: item.rawValue,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    static func save(_ data: Data, as item: Item) throws {
        delete(item)
        var query = baseQuery(item)
        query[kSecValueData] = data
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func read(_ item: Item) -> Data? {
        var query = baseQuery(item)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func delete(_ item: Item) -> Bool {
        SecItemDelete(baseQuery(item) as CFDictionary) == errSecSuccess
    }

    /// Stores [data] so that reading it requires the currently enrolled biometrics.
    static func saveBiometricProtected(_ data: Data, as item: Item) throws {
        delete(item)
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error
        ) else { throw error!.takeRetainedValue() as Error }
        var query = baseQuery(item)
        query[kSecValueData] = data
        query[kSecAttrAccessControl] = access
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    /// Shows the biometric prompt and returns the item. Blocks: call off the main thread.
    static func readBiometricProtected(_ item: Item, reason: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = "Use Password"
        var query = baseQuery(item)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext] = context
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.status(errSecDecode) }
            return data
        case errSecUserCanceled, errSecAuthFailed:
            throw KeychainError.cancelled
        default:
            throw KeychainError.status(status)
        }
    }
}
