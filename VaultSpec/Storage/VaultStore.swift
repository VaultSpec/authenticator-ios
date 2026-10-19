import CryptoKit
import Foundation
import LocalAuthentication
import Observation

/// The vault: the encrypted list of accounts and the keys that open it.
///
/// A random 256-bit master key encrypts the account list (AES-256-GCM) in a protected file.
/// The master key is stored twice in the Keychain: wrapped with a key derived from the vault
/// password (PBKDF2), and — if enabled — on its own behind Face ID / Touch ID.
@Observable
final class VaultStore {
    enum State: Equatable { case needsSetup, locked, unlocked }

    nonisolated enum VaultError: LocalizedError {
        case wrongPassword, passwordTooShort, corrupted

        var errorDescription: String? {
            switch self {
            case .wrongPassword: "Incorrect password."
            case .passwordTooShort: "Use at least \(VaultStore.minimumPasswordLength) characters."
            case .corrupted: "The vault could not be read."
            }
        }
    }

    nonisolated static let minimumPasswordLength = 8

    private(set) var state: State
    private(set) var accounts: [Account] = []
    private(set) var biometricsEnabled: Bool
    /// Goes up on every change to the accounts (not on lock or unlock); drives automatic backups.
    private(set) var revision = 0
    private var masterKey: SymmetricKey?

    private nonisolated struct PasswordSlot: Codable {
        let salt: Data
        let wrappedKey: Data
    }

    private static let biometricsFlag = "biometricsEnabled"

    private static var vaultFile: URL {
        URL.applicationSupportDirectory.appending(path: "vault.bin")
    }

    init() {
        state = Keychain.read(.passwordSlot) == nil ? .needsSetup : .locked
        biometricsEnabled = UserDefaults.standard.bool(forKey: Self.biometricsFlag)
    }

    // MARK: Biometrics

    /// "Face ID", "Touch ID", "Optic ID", or nil when the device has none enrolled.
    var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        return switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: nil
        }
    }

    var biometrySymbol: String {
        LAContext().biometryType == .touchID ? "touchid" : "faceid"
    }

    // MARK: Lifecycle

    /// Creates the vault. [restoring] accepts a shorter password, because a restored backup was
    /// already made with it on another device.
    func setUp(password: String, enableBiometrics: Bool, restoring: Bool = false) async throws {
        guard restoring || password.count >= Self.minimumPasswordLength else { throw VaultError.passwordTooShort }
        let key = SymmetricKey(size: .bits256)
        try await storePasswordSlot(for: key, password: password)
        masterKey = key
        accounts = []
        try persist()
        if enableBiometrics { try? setBiometrics(enabled: true) }
        state = .unlocked
    }

    func unlock(password: String) async throws {
        guard let slotData = Keychain.read(.passwordSlot),
              let slot = try? JSONDecoder().decode(PasswordSlot.self, from: slotData)
        else { throw VaultError.corrupted }
        let key = try await Task.detached(priority: .userInitiated) {
            let wrappingKey = try VaultCrypto.deriveKey(password: password, salt: slot.salt)
            guard let raw = try? VaultCrypto.open(slot.wrappedKey, with: wrappingKey) else {
                throw VaultError.wrongPassword
            }
            return SymmetricKey(data: raw)
        }.value
        try open(with: key)
    }

    /// Checks [password] against the vault without changing anything.
    func verifyPassword(_ password: String) async -> Bool {
        guard let slotData = Keychain.read(.passwordSlot),
              let slot = try? JSONDecoder().decode(PasswordSlot.self, from: slotData)
        else { return false }
        return await Task.detached(priority: .userInitiated) {
            guard let wrappingKey = try? VaultCrypto.deriveKey(password: password, salt: slot.salt) else { return false }
            return (try? VaultCrypto.open(slot.wrappedKey, with: wrappingKey)) != nil
        }.value
    }

    func unlockWithBiometrics() async throws {
        let reason = "Unlock your vault"
        let raw = try await Task.detached(priority: .userInitiated) {
            try Keychain.readBiometricProtected(.biometricKey, reason: reason)
        }.value
        try open(with: SymmetricKey(data: raw))
    }

    func lock() {
        guard state == .unlocked else { return }
        masterKey = nil
        accounts = []
        state = .locked
    }

    /// Permanently deletes the vault and its keys from this device.
    func erase() {
        try? FileManager.default.removeItem(at: Self.vaultFile)
        Keychain.delete(.passwordSlot)
        Keychain.delete(.biometricKey)
        UserDefaults.standard.removeObject(forKey: Self.biometricsFlag)
        biometricsEnabled = false
        masterKey = nil
        accounts = []
        state = .needsSetup
    }

    // MARK: Settings

    func setBiometrics(enabled: Bool) throws {
        if enabled {
            guard let masterKey else { return }
            try Keychain.saveBiometricProtected(masterKey.withUnsafeBytes { Data($0) }, as: .biometricKey)
        } else {
            Keychain.delete(.biometricKey)
        }
        biometricsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.biometricsFlag)
    }

    func changePassword(to password: String) async throws {
        guard password.count >= Self.minimumPasswordLength else { throw VaultError.passwordTooShort }
        guard let masterKey else { return }
        try await storePasswordSlot(for: masterKey, password: password)
    }

    // MARK: Accounts

    func add(_ account: Account) throws {
        accounts.append(account)
        try persist()
        revision += 1
    }

    func delete(_ account: Account) throws {
        accounts.removeAll { $0.id == account.id }
        try persist()
        revision += 1
    }

    /// Adds restored accounts, skipping any already in the vault. Returns how many were added.
    @discardableResult
    func importAccounts(_ restored: [Account]) throws -> Int {
        let existing = Set(accounts.map(\.identity))
        var seen = existing
        let added = restored.filter { seen.insert($0.identity).inserted }
        guard !added.isEmpty else { return 0 }
        accounts.append(contentsOf: added)
        try persist()
        revision += 1
        return added.count
    }

    // MARK: Storage

    private func storePasswordSlot(for key: SymmetricKey, password: String) async throws {
        let rawKey = key.withUnsafeBytes { Data($0) }
        let slot = try await Task.detached(priority: .userInitiated) {
            let salt = VaultCrypto.randomBytes(16)
            let wrappingKey = try VaultCrypto.deriveKey(password: password, salt: salt)
            return PasswordSlot(salt: salt, wrappedKey: try VaultCrypto.seal(rawKey, with: wrappingKey))
        }.value
        try Keychain.save(try JSONEncoder().encode(slot), as: .passwordSlot)
    }

    private func open(with key: SymmetricKey) throws {
        if let sealed = try? Data(contentsOf: Self.vaultFile) {
            guard let plain = try? VaultCrypto.open(sealed, with: key),
                  let decoded = try? JSONDecoder().decode([Account].self, from: plain)
            else { throw VaultError.corrupted }
            accounts = decoded
        } else {
            accounts = []
        }
        masterKey = key
        state = .unlocked
    }

    private func persist() throws {
        guard let masterKey else { return }
        let sealed = try VaultCrypto.seal(try JSONEncoder().encode(accounts), with: masterKey)
        try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try sealed.write(to: Self.vaultFile, options: [.atomic, .completeFileProtection])
    }
}

#if DEBUG
extension VaultStore {
    /// Launch with `-demoVault` for screenshots: creates a vault with sample accounts, unlocked
    /// unless `-demoLocked` is also passed.
    func seedDemoIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-demoVault") else { return }
        erase()
        do {
            try await setUp(password: "demo-vault-1", enableBiometrics: false)
        } catch {
            // No Keychain access (for example an unsigned Mac build): keep the demo in memory only
            masterKey = SymmetricKey(size: .bits256)
            state = .unlocked
        }
        let samples: [(String, String, String)] = [
            ("AWS", "alex@northwind.io", "Work"),
            ("GitHub", "alex-dev", "Work"),
            ("Okta", "alex@northwind.io", "Work"),
            ("Google Workspace", "alex@northwind.io", "Work"),
            ("Microsoft 365", "alex@northwind.io", "Work"),
            ("Cloudflare", "alex@northwind.io", "Work"),
            ("Stripe", "finance@northwind.io", "Work"),
            ("Slack", "alex@northwind.io", "Work"),
            ("Google", "alex@example.com", "Personal"),
            ("Proton", "alex@proton.me", "Personal"),
        ]
        for (issuer, name, category) in samples {
            try? add(Account(issuer: issuer, name: name, secret: Base32.encode(VaultCrypto.randomBytes(20)), category: category))
        }
        // `-demoLocked` shows the lock screen over the sample vault
        if ProcessInfo.processInfo.arguments.contains("-demoLocked") { lock() }
    }
}
#endif
