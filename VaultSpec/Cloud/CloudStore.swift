import Foundation
import Observation
import UIKit

/// Encrypted backups in the user's VaultSpec account.
///
/// Backups are encrypted with a key derived from the vault password, so the server only ever
/// stores ciphertext. The password itself is not kept: the derived key and its salt are stored in
/// the Keychain, which lets automatic backups run after a Face ID / Touch ID unlock. Changing the
/// vault password derives a new key, and the server then drops every backup made with the old one.
@Observable
final class CloudStore {
    nonisolated enum CloudError: LocalizedError {
        /// The account already holds backups from another vault; uploading would replace them.
        case existingBackup
        case notEnabled
        case vaultLocked

        var errorDescription: String? {
            switch self {
            case .existingBackup: "This account already has a cloud backup."
            case .notEnabled: "Cloud backup is off."
            case .vaultLocked: "Unlock the vault first."
            }
        }
    }

    private let api: CloudAPI
    private(set) var email: String?
    private(set) var isEnabled: Bool
    private(set) var lastBackupAt: Date?
    /// A backup failed (usually offline) and will be retried on the next change or unlock.
    private(set) var isPending: Bool
    private(set) var isUploading = false
    private(set) var lastError: String?

    private var autoBackupTask: Task<Void, Never>?
    private let defaults: UserDefaults

    private static let enabledFlag = "cloud.enabled"
    private static let pendingFlag = "cloud.pending"
    private static let lastBackupKey = "cloud.lastBackupAt"

    var isSignedIn: Bool { email != nil }

    init(api: CloudAPI = CloudAPI(), defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledFlag) && Keychain.read(.cloudKey) != nil
        isPending = defaults.bool(forKey: Self.pendingFlag)
        lastBackupAt = defaults.object(forKey: Self.lastBackupKey) as? Date
        Task { email = await api.email }
    }

    // MARK: Account

    func register(email: String, password: String) async throws {
        try await api.register(email: email, password: password)
    }

    func requestCode(email: String, password: String) async throws {
        try await api.requestCode(email: email, password: password)
    }

    func verify(email: String, password: String, code: String) async throws {
        let session = try await api.verify(email: email, password: password, code: code, deviceName: UIDevice.current.name)
        self.email = session.email
    }

    func forgotPassword(email: String) async throws {
        try await api.forgotPassword(email: email)
    }

    func signOut() async {
        disable()
        await api.signOut()
        email = nil
    }

    func deleteAccount(password: String) async throws {
        try await api.deleteAccount(password: password)
        disable()
        email = nil
    }

    // MARK: Backing up

    /// Turns cloud backup on and uploads the first backup. The caller has already checked
    /// [vaultPassword] against the vault.
    ///
    /// Throws `CloudError.existingBackup` if the account already has backups and
    /// [replaceExisting] is false: they belong to another vault and uploading would delete them.
    func enable(vaultPassword: String, accounts: [Account], replaceExisting: Bool = false) async throws {
        if !replaceExisting {
            let existing = try await api.listBackups()
            if !existing.isEmpty { throw CloudError.existingBackup }
        }
        try await storeKey(for: vaultPassword)
        setEnabled(true)
        try await upload(accounts)
    }

    /// Stops backing up from this device. Backups already in the cloud stay.
    func disable() {
        autoBackupTask?.cancel()
        Keychain.delete(.cloudKey)
        setEnabled(false)
        setPending(false)
    }

    func backupNow(_ accounts: [Account]) async throws {
        guard isEnabled else { throw CloudError.notEnabled }
        autoBackupTask?.cancel()
        try await upload(accounts)
    }

    /// Backs up shortly after the accounts change, so several quick edits make one upload.
    func scheduleBackup(_ accounts: [Account]) {
        guard isEnabled else { return }
        autoBackupTask?.cancel()
        autoBackupTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? await upload(accounts)
        }
    }

    /// Re-keys after the vault password changed and uploads, which makes the server delete every
    /// backup made with the old password. If the upload fails it is retried later.
    func vaultPasswordChanged(to password: String, accounts: [Account]) async {
        guard isEnabled else { return }
        do {
            try await storeKey(for: password)
            try await upload(accounts)
        } catch {
            setPending(true)
        }
    }

    // MARK: Restoring

    /// The newest backup in the account, or nil if there is none.
    func fetchLatest() async throws -> (payload: BackupPayload, createdAt: Date?)? {
        guard let remote = try await api.latestBackup() else { return nil }
        guard let payload = try? JSONDecoder().decode(BackupPayload.self, from: Data(remote.payload.utf8)) else {
            throw BackupFormat.FormatError.unreadable
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (payload, formatter.date(from: remote.createdAt))
    }

    func decrypt(_ payload: BackupPayload, vaultPassword: String) async throws -> [Account] {
        try await Task.detached(priority: .userInitiated) {
            try BackupFormat.decrypt(payload, password: vaultPassword)
        }.value
    }

    /// Keeps backing up under [vaultPassword] after a vault was restored with it, without uploading.
    func adopt(vaultPassword: String) async throws {
        try await storeKey(for: vaultPassword)
        setEnabled(true)
    }

    // MARK: Private

    private func storeKey(for password: String) async throws {
        let key = try await Task.detached(priority: .userInitiated) {
            try BackupFormat.deriveKey(password: password)
        }.value
        try Keychain.save(try JSONEncoder().encode(key), as: .cloudKey)
    }

    private func upload(_ accounts: [Account]) async throws {
        guard let stored = Keychain.read(.cloudKey), let key = try? JSONDecoder().decode(BackupFormat.Key.self, from: stored) else {
            throw CloudError.notEnabled
        }
        isUploading = true
        defer { isUploading = false }
        do {
            let payload = try BackupFormat.encrypt(accounts, with: key)
            let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
            _ = try await api.upload(keyId: key.keyId, payload: json)
            lastBackupAt = .now
            defaults.set(lastBackupAt, forKey: Self.lastBackupKey)
            setPending(false)
            lastError = nil
        } catch let failure as CloudAPI.Failure where failure.code == "unauthorized" {
            // Signed out remotely (password reset or account deleted): stop trying
            disable()
            email = nil
            lastError = failure.localizedDescription
            throw failure
        } catch {
            setPending(true)
            lastError = error.localizedDescription
            throw error
        }
    }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledFlag)
    }

    private func setPending(_ pending: Bool) {
        isPending = pending
        defaults.set(pending, forKey: Self.pendingFlag)
    }
}
