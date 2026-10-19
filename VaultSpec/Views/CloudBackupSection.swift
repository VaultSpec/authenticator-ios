import SwiftUI

/// The sheets the Cloud Backup section opens. They are presented by the Settings screen itself:
/// SwiftUI copies a Section's modifiers onto each of its rows, so a sheet or dialog attached to the
/// section is presented several times at once, and UIKit then dismisses Settings.
enum CloudSheet: String, Identifiable {
    case signIn, enable, restore, delete
    var id: String { rawValue }
}

/// The "Cloud Backup" group in Settings.
struct CloudBackupSection: View {
    @Binding var sheet: CloudSheet?
    @Binding var confirmingSignOut: Bool
    @Environment(CloudStore.self) private var cloud
    @Environment(VaultStore.self) private var vault
    @State private var error: String?

    var body: some View {
        Section {
            if let email = cloud.email {
                LabeledContent("Account", value: email)

                Toggle(isOn: Binding(
                    get: { cloud.isEnabled },
                    set: { on in
                        if on { sheet = .enable } else { cloud.disable() }
                    }
                )) {
                    Label("Back Up Automatically", systemImage: "cloud")
                }

                if cloud.isEnabled {
                    Button(action: backUpNow) {
                        HStack {
                            Label("Back Up Now", systemImage: "arrow.clockwise")
                            Spacer()
                            if cloud.isUploading { ProgressView() }
                        }
                    }
                    .disabled(cloud.isUploading)

                    LabeledContent("Last Backup") {
                        Text(lastBackup).foregroundStyle(cloud.isPending ? .orange : .secondary)
                    }
                }

                Button("Restore from Cloud", systemImage: "arrow.down.circle") { sheet = .restore }
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") { confirmingSignOut = true }
                Button("Delete Cloud Account", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                    sheet = .delete
                }
            } else {
                Button("Sign In or Create Account", systemImage: "person.crop.circle.badge.plus") { sheet = .signIn }
            }

            if let error {
                Text(error).foregroundStyle(.red)
            }
        } header: {
            Text("Cloud Backup")
        } footer: {
            Text(cloud.isSignedIn
                ? "Backups are encrypted with your vault password before they leave this device, so VaultSpec can't read them. The newest 3 are kept."
                : "Keep an encrypted backup in a VaultSpec account and restore it on a new iPhone, iPad, Mac or Android phone.")
        }
    }

    @ViewBuilder
    static func content(for sheet: CloudSheet, cloud: CloudStore) -> some View {
        switch sheet {
        case .signIn: CloudSignInView()
        case .enable: EnableCloudBackupView()
        case .restore: CloudRestoreView(mode: .merge)
        case .delete:
            PasswordPromptView(
                title: "Delete Cloud Account",
                placeholder: "Account password",
                message: "Deletes your VaultSpec account and every backup in it. Accounts on this device are not affected.",
                actionTitle: "Delete Account",
                role: .destructive
            ) { password in
                try await cloud.deleteAccount(password: password)
            }
        }
    }

    private var lastBackup: String {
        if cloud.isPending { return "Waiting to retry" }
        guard let date = cloud.lastBackupAt else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    private func backUpNow() {
        error = nil
        Task {
            do {
                try await cloud.backupNow(vault.accounts)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Turns on cloud backup: the vault password derives the backup key.
private struct EnableCloudBackupView: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @State private var needsReplaceConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Vault password", text: $password)
                        .textContentType(.password)
                        .onSubmit { enable(replacing: false) }
                } footer: {
                    Text("Backups are encrypted with your vault password on this device. You'll need it to restore them, and VaultSpec can't reset it.")
                }

                if needsReplaceConfirmation {
                    Section {
                        Button("Replace Cloud Backup", role: .destructive) { enable(replacing: true) }
                    } footer: {
                        Text("This account already has a backup from another vault. Backing up this device will delete it. To keep those accounts, restore them first.")
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background { Backdrop() }
            .navigationTitle("Turn On Cloud Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Turn On", systemImage: "checkmark") { enable(replacing: false) }
                            .buttonStyle(.glassProminent)
                            .disabled(password.isEmpty)
                    }
                }
            }
        }
    }

    private func enable(replacing: Bool) {
        guard !password.isEmpty, !working else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            guard await vault.verifyPassword(password) else {
                error = VaultStore.VaultError.wrongPassword.localizedDescription
                return
            }
            do {
                try await cloud.enable(vaultPassword: password, accounts: vault.accounts, replaceExisting: replacing)
                dismiss()
            } catch CloudStore.CloudError.existingBackup {
                needsReplaceConfirmation = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A sheet that asks for one password and runs an action with it.
struct PasswordPromptView: View {
    let title: String
    let placeholder: String
    let message: String
    let actionTitle: String
    var role: ButtonRole?
    let action: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(placeholder, text: $password)
                        .textContentType(.password)
                        .onSubmit(run)
                } footer: {
                    Text(message)
                }
                Section {
                    Button(role: role, action: run) {
                        HStack {
                            Text(actionTitle)
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(password.isEmpty || working)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background { Backdrop() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func run() {
        guard !password.isEmpty, !working else { return }
        working = true
        error = nil
        Task {
            do {
                try await action(password)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
