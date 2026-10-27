import SwiftUI

/// First launch: create the vault password.
struct SetupView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
    @Environment(CloudStore.self) private var cloud
    @State private var password = ""
    @State private var confirmation = ""
    @State private var enableBiometrics = true
    @State private var error: String?
    @State private var working = false
    @State private var showingRestore = false
    @State private var showingConnect = false
    @State private var restored: RestoredBackup?
    @FocusState private var focused: Field?

    private enum Field { case password, confirmation }
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        CenteredScroll {
            AdaptiveStack(spacing: 28) {
                VStack(spacing: 14) {
                    LogoMark().frame(width: 76, height: 76)
                    Text("Create Your Vault")
                        .font(.largeTitle.weight(.bold))
                    Text("Your vault password encrypts every code on this device. It is never stored or sent anywhere.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                VStack(spacing: 20) {
                    fields

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    Button(action: create) {
                        Group {
                            if working { ProgressView() } else { Text("Create Vault").fontWeight(.semibold) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working)

                    Text("At least \(VaultStore.minimumPasswordLength) characters. If you forget it, the vault cannot be recovered.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Restore from VaultSpec Cloud", systemImage: "arrow.down.circle") { showingRestore = true }
                        .buttonStyle(.glass)
                        .controlSize(.large)

                    if ScanToConnectView.isSupported {
                        Button("Use Another Device", systemImage: "qrcode.viewfinder") { showingConnect = true }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: verticalSizeClass == .compact ? 880 : 520)
        }
        .sheet(isPresented: $showingRestore, onDismiss: finishRestore) {
            CloudRestoreView(mode: .newVault) { restored = $0 }
                .presentationSizing(.form)
        }
        .fullScreenCover(isPresented: $showingConnect, onDismiss: finishRestore) {
            ScanToConnectView { restored = $0 }
        }
        #if DEBUG
        .task { if UserDefaults.standard.string(forKey: "screen") == "scan" { showingConnect = true } }
        #endif
    }

    private var fields: some View {
        GlassEffectContainer {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    SecureField("Vault password", text: $password)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focused = .confirmation }
                        .padding(18)
                    Divider().padding(.leading, 18)
                    SecureField("Confirm password", text: $confirmation)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .confirmation)
                        .submitLabel(.go)
                        .onSubmit(create)
                        .padding(18)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 24))

                if let biometry = vault.biometryName {
                    Toggle(isOn: $enableBiometrics) {
                        Label("Unlock with \(biometry)", systemImage: vault.biometrySymbol)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                }
            }
        }
    }

    private func create() {
        error = nil
        guard password.count >= VaultStore.minimumPasswordLength else {
            error = VaultStore.VaultError.passwordTooShort.localizedDescription
            return
        }
        guard password == confirmation else {
            error = "The passwords don't match."
            return
        }
        working = true
        Task {
            do {
                try await vault.setUp(password: password, enableBiometrics: enableBiometrics && vault.biometryName != nil)
                settings.recordPasswordEntry()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }

    /// Runs once the restore or connect sheet has closed: the backup's vault password becomes this vault's.
    private func finishRestore() {
        guard let backup = restored else { return }
        restored = nil
        error = nil
        working = true
        Task {
            do {
                try await vault.setUp(password: backup.password, enableBiometrics: backup.enableBiometrics, restoring: true)
                try vault.importAccounts(backup.accounts)
                settings.recordPasswordEntry()
                // Future backups use this device's key; failing here only delays them
                try? await cloud.adopt(vaultPassword: backup.password)
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
