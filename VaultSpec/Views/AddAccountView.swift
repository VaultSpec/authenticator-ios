import SwiftUI

/// Add an account by scanning its QR code, pasting an otpauth link, or typing the setup key.
struct AddAccountView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss

    @State private var issuer = ""
    @State private var name = ""
    @State private var secret = ""
    @State private var algorithm = Account.Algorithm.sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var category = Account.defaultCategory
    @State private var error: String?
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            Form {
                if ScannerView.isSupported {
                    Section {
                        Button {
                            showingScanner = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "qrcode.viewfinder")
                                Text("Scan QR Code")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.glassProminent)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    Button("Paste Setup Link", systemImage: "doc.on.clipboard", action: pasteLink)
                } footer: {
                    Text(ScannerView.isSupported
                        ? "Most sites show a QR code when you turn on two-factor authentication."
                        : "Copy the setup link or key from the site's two-factor settings.")
                }

                Section("Or enter it yourself") {
                    TextField("Service, e.g. GitHub", text: $issuer)
                        .textInputAutocapitalization(.words)
                    TextField("Account name or email", text: $name)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TextField("Setup key", text: $secret)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(Account.categories, id: \.self, content: Text.init)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Advanced") {
                    Picker("Algorithm", selection: $algorithm) {
                        ForEach(Account.Algorithm.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    Picker("Digits", selection: $digits) {
                        Text("6").tag(6)
                        Text("8").tag(8)
                    }
                    Picker("Period", selection: $period) {
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background { Backdrop() }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(secret.isEmpty)
                }
            }
            .sheet(isPresented: $showingScanner) {
                ScannerView { link in
                    showingScanner = false
                    use(link)
                }
            }
        }
    }

    private func pasteLink() {
        guard let text = UIPasteboard.general.string else {
            error = "The clipboard is empty."
            return
        }
        use(text)
    }

    /// Fills the form from an otpauth link and saves straight away.
    private func use(_ link: String) {
        do {
            var account = try OTPAuthURI.parse(link)
            account.category = category
            try vault.add(account)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        let key = Base32.normalize(secret)
        guard let bytes = Base32.decode(key), bytes.count >= 10 else {
            error = "That setup key isn't valid. It should only contain letters A–Z and digits 2–7."
            return
        }
        guard !issuer.trimmingCharacters(in: .whitespaces).isEmpty || !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Enter the service or the account name."
            return
        }
        do {
            try vault.add(Account(
                issuer: issuer.trimmingCharacters(in: .whitespaces),
                name: name.trimmingCharacters(in: .whitespaces),
                secret: key, algorithm: algorithm, digits: digits, period: period, category: category
            ))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
