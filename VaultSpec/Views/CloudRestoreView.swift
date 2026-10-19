import SwiftUI

/// Restores the newest backup from VaultSpec Cloud, made on any device (Android included).
///
/// `.newVault` runs during setup: the backup's vault password becomes this vault's password.
/// `.merge` adds the backup's accounts to the unlocked vault, skipping ones already there.
struct CloudRestoreView: View {
    enum Mode { case newVault, merge }
    let mode: Mode
    /// `.newVault`: receives the opened backup; the presenter creates the vault after this sheet closes.
    var onRestored: ((RestoredBackup) -> Void)? = nil

    @Environment(CloudStore.self) private var cloud
    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss

    private enum Remote {
        case loading
        case none
        case found(BackupPayload, Date?)
        case failed(String)
    }

    @State private var remote = Remote.loading
    @State private var showingSignIn = false
    @State private var password = ""
    @State private var enableBiometrics = true
    @State private var working = false
    @State private var error: String?
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                if !cloud.isSignedIn {
                    Section {
                        Button("Sign In", systemImage: "person.crop.circle") { showingSignIn = true }
                    } footer: {
                        Text("Sign in to the VaultSpec account your backup is in.")
                    }
                } else if let result {
                    Section {
                        Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                } else {
                    backupSection
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background { Backdrop() }
            .navigationTitle("Restore from Cloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if result == nil {
                        Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if result != nil {
                        Button("Done", systemImage: "checkmark") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showingSignIn) { CloudSignInView() }
            .task(id: cloud.email) { await load() }
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        switch remote {
        case .loading:
            Section {
                HStack {
                    ProgressView()
                    Text("Looking for backups…").foregroundStyle(.secondary)
                }
            }
        case .none:
            Section {
                Label("No backups in \(cloud.email ?? "this account") yet.", systemImage: "tray")
            }
        case .failed(let message):
            Section {
                Text(message).foregroundStyle(.red)
                Button("Try Again", systemImage: "arrow.clockwise") { Task { await load() } }
            }
        case .found(let payload, let date):
            Section {
                LabeledContent("Account", value: cloud.email ?? "")
                if let date {
                    LabeledContent("Backed Up", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section {
                SecureField("Vault password", text: $password)
                    .textContentType(.password)
                    .onSubmit { restore(payload) }
                if mode == .newVault, let biometry = vault.biometryName {
                    Toggle(isOn: $enableBiometrics) {
                        Label("Unlock with \(biometry)", systemImage: vault.biometrySymbol)
                    }
                }
            } footer: {
                Text(mode == .newVault
                    ? "Enter the vault password the backup was made with. It becomes this vault's password."
                    : "Enter the vault password the backup was made with. Accounts already on this device are skipped.")
            }

            Section {
                Button { restore(payload) } label: {
                    Group {
                        if working { ProgressView() } else { Text("Restore").fontWeight(.semibold) }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || working)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
    }

    private func load() async {
        guard cloud.isSignedIn else { return }
        remote = .loading
        do {
            if let latest = try await cloud.fetchLatest() {
                remote = .found(latest.payload, latest.createdAt)
            } else {
                remote = .none
            }
        } catch {
            remote = .failed(error.localizedDescription)
        }
    }

    private func restore(_ payload: BackupPayload) {
        guard !password.isEmpty, !working else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                let accounts = try await cloud.decrypt(payload, vaultPassword: password)
                switch mode {
                case .newVault:
                    // Creating the vault swaps the setup screen for the home screen. Doing that while
                    // this sheet is up removes the view presenting it, and the sheet is left stuck on
                    // screen (Mac Catalyst). So close first and let the presenter finish.
                    onRestored?(RestoredBackup(
                        accounts: accounts, password: password,
                        enableBiometrics: enableBiometrics && vault.biometryName != nil
                    ))
                    dismiss()
                case .merge:
                    let added = try vault.importAccounts(accounts)
                    result = switch added {
                    case 0: "Everything in the backup is already on this device."
                    case 1: "Restored 1 account."
                    default: "Restored \(added) accounts."
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A backup that opened with its vault password, ready to become this device's vault.
struct RestoredBackup {
    let accounts: [Account]
    let password: String
    let enableBiometrics: Bool
}
