import SwiftUI

struct SettingsView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var showingPassword = false
    @State private var confirmingErase = false
    @State private var cloudSheet: CloudSheet?
    @State private var error: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Security") {
                    if let biometry = vault.biometryName {
                        Toggle(isOn: Binding(
                            get: { vault.biometricsEnabled },
                            set: { enabled in
                                do { try vault.setBiometrics(enabled: enabled) } catch { self.error = error.localizedDescription }
                            }
                        )) {
                            Label("Unlock with \(biometry)", systemImage: vault.biometrySymbol)
                        }
                    }
                    Button("Change Vault Password", systemImage: "key") { showingPassword = true }
                    Button("Lock Now", systemImage: "lock") {
                        dismiss()
                        vault.lock()
                    }
                }

                CloudBackupSection(sheet: $cloudSheet)

                Section {
                    LabeledContent("Accounts", value: "\(vault.accounts.count)")
                    LabeledContent("Encryption", value: "AES-256-GCM")
                } header: {
                    Text("Vault")
                } footer: {
                    Text("Codes are generated on this device. The vault locks whenever VaultSpec leaves the screen.")
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    Link(destination: URL(string: "https://www.vaultspec.in/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://www.vaultspec.in")!) {
                        Label("vaultspec.in", systemImage: "safari")
                    }
                }

                Section {
                    Button("Erase Vault", systemImage: "trash", role: .destructive) { confirmingErase = true }
                } footer: {
                    Text("Deletes every account and key from this device. This cannot be undone.")
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background { Backdrop() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPassword) { ChangePasswordView() }
            .sheet(item: $cloudSheet) { CloudBackupSection.content(for: $0, cloud: cloud) }
            .confirmationDialog("Erase this vault?", isPresented: $confirmingErase, titleVisibility: .visible) {
                Button("Erase Vault", role: .destructive) {
                    dismiss()
                    cloud.disable()
                    vault.erase()
                }
            } message: {
                Text("All accounts on this device will be deleted. You'll need to add them again to generate codes.")
            }
        }
    }
}

private struct ChangePasswordView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $password).textContentType(.newPassword)
                    SecureField("Confirm new password", text: $confirmation).textContentType(.newPassword)
                } footer: {
                    Text("At least \(VaultStore.minimumPasswordLength) characters.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(working)
                }
            }
        }
    }

    private func save() {
        guard password == confirmation else {
            error = "The passwords don't match."
            return
        }
        working = true
        Task {
            do {
                try await vault.changePassword(to: password)
                // Cloud backups move to the new password; the server then drops the old ones
                await cloud.vaultPasswordChanged(to: password, accounts: vault.accounts)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
