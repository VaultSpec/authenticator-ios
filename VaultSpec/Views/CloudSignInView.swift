import SwiftUI

/// Signs in to, or creates, a VaultSpec account: email and account password, then the
/// six-digit code sent by email.
struct CloudSignInView: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    var onSignedIn: () -> Void = {}

    private enum Mode: String, CaseIterable { case signIn = "Sign In", create = "Create Account" }
    private enum Step { case credentials, code }
    private enum Field { case email, password, code }

    @State private var mode = Mode.signIn
    @State private var step = Step.credentials
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var working = false
    @State private var error: String?
    @State private var notice: String?
    @FocusState private var focused: Field?

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .credentials: credentials
                case .code: codeEntry
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if let notice {
                    Section { Text(notice).foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .background { Backdrop() }
            .navigationTitle("VaultSpec Cloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
            .animation(.smooth, value: step)
            .onAppear { focused = .email }
        }
    }

    @ViewBuilder
    private var credentials: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }

        Section {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
            SecureField("Account password", text: $password)
                .textContentType(mode == .create ? .newPassword : .password)
                .focused($focused, equals: .password)
                .submitLabel(.continue)
                .onSubmit(submitCredentials)
        } footer: {
            Text(mode == .create
                ? "Your account password signs you in. Your vault password is separate: it encrypts your backups and never leaves this device."
                : "We'll email you a 6-digit code to finish signing in.")
        }

        Section {
            primaryButton(mode == .create ? "Create Account" : "Continue", action: submitCredentials)
                .disabled(trimmedEmail.isEmpty || password.isEmpty)
        }

        if mode == .signIn {
            Section {
                Button("Forgot Account Password?", action: forgotPassword)
                    .disabled(trimmedEmail.isEmpty || working)
            }
        }
    }

    @ViewBuilder
    private var codeEntry: some View {
        Section {
            TextField("6-digit code", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .focused($focused, equals: .code)
                .onChange(of: code) { _, value in
                    code = String(value.filter(\.isNumber).prefix(6))
                    if code.count == 6 { verify() }
                }
        } header: {
            Text("Check your email")
        } footer: {
            Text("We sent a code to \(trimmedEmail). It expires in a few minutes.")
        }

        Section {
            primaryButton("Verify", action: verify)
                .disabled(code.count != 6)
        }

        Section {
            Button("Send a New Code", systemImage: "arrow.clockwise", action: resendCode)
                .disabled(working)
            Button("Use a Different Email", systemImage: "chevron.backward") {
                step = .credentials
                code = ""
                error = nil
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if working { ProgressView() } else { Text(title).fontWeight(.semibold) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.defaultAction)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func submitCredentials() {
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return }
        if mode == .create, password.count < 8 {
            error = "Use at least 8 characters for the account password."
            return
        }
        run {
            if mode == .create {
                try await cloud.register(email: trimmedEmail, password: password)
            } else {
                try await cloud.requestCode(email: trimmedEmail, password: password)
            }
            step = .code
            focused = .code
        }
    }

    private func resendCode() {
        run {
            try await cloud.requestCode(email: trimmedEmail, password: password)
            notice = "A new code is on its way."
        }
    }

    private func verify() {
        guard code.count == 6, !working else { return }
        run {
            try await cloud.verify(email: trimmedEmail, password: password, code: code)
            onSignedIn()
            dismiss()
        } onError: {
            code = ""
        }
    }

    private func forgotPassword() {
        run {
            try await cloud.forgotPassword(email: trimmedEmail)
            notice = "If \(trimmedEmail) has an account, we've emailed a link to reset its password."
        }
    }

    private func run(_ work: @escaping () async throws -> Void, onError: @escaping () -> Void = {}) {
        working = true
        error = nil
        notice = nil
        Task {
            do {
                try await work()
            } catch {
                self.error = error.localizedDescription
                onError()
            }
            working = false
        }
    }
}
