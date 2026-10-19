import SwiftUI

/// Locked vault: password, or Face ID / Touch ID when enabled.
struct LockView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
    @State private var password = ""
    @State private var error: String?
    @State private var working = false
    @State private var attempts = 0
    @FocusState private var focused: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        CenteredScroll {
            AdaptiveStack(spacing: 32) {
                VStack(spacing: 14) {
                    LogoMark().frame(width: 88, height: 88)
                    Text("Welcome Back")
                        .font(.largeTitle.weight(.bold))
                    Text(reminderDue
                        ? "Enter your vault password. For your security, VaultSpec asks for it every \(settings.passwordReminderDays) days."
                        : "Unlock your vault to see your codes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                VStack(spacing: 20) {
                    unlockForm
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: verticalSizeClass == .compact ? 880 : 520)
        }
        .sensoryFeedback(.error, trigger: attempts)
        .task {
            if canUseBiometrics {
                unlockWithBiometrics()
            } else {
                focused = true
            }
        }
    }

    /// The periodic password check: biometrics stay off until the password is entered.
    private var reminderDue: Bool { settings.isPasswordReminderDue() }

    private var canUseBiometrics: Bool {
        vault.biometricsEnabled && vault.biometryName != nil && !reminderDue
    }

    private var unlockForm: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    SecureField("Vault password", text: $password)
                        .textContentType(.password)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(unlockWithPassword)
                }
                .padding(18)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .phaseAnimator([0, 1, 0], trigger: attempts) { content, phase in
                    content.offset(x: phase * 10)
                } animation: { _ in .spring(duration: 0.12) }

                HStack(spacing: 12) {
                    Button(action: unlockWithPassword) {
                        Group {
                            if working { ProgressView() } else { Text("Unlock").fontWeight(.semibold) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || working)

                    if canUseBiometrics {
                        Button(action: unlockWithBiometrics) {
                            Image(systemName: vault.biometrySymbol)
                                .font(.title2)
                                .frame(width: 30, height: 30)
                                .padding(4)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Unlock with \(vault.biometryName ?? "biometrics")")
                    }
                }
                .controlSize(.large)
            }
        }
    }

    private func unlockWithPassword() {
        guard !password.isEmpty, !working else { return }
        working = true
        error = nil
        Task {
            do {
                try await vault.unlock(password: password)
                settings.recordPasswordEntry()
            } catch {
                self.error = error.localizedDescription
                attempts += 1
                password = ""
            }
            working = false
        }
    }

    private func unlockWithBiometrics() {
        Task {
            do {
                try await vault.unlockWithBiometrics()
            } catch Keychain.KeychainError.cancelled {
                focused = true
            } catch {
                self.error = "\(vault.biometryName ?? "Biometric unlock") failed. Use your password."
                focused = true
            }
        }
    }
}
