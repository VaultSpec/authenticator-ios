import SwiftUI

/// Add an account by scanning its QR code, pasting an otpauth link, or typing the setup key.
struct AddAccountView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
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
    @State private var namingCategory = false
    @State private var newCategory = ""
    @Namespace private var chips

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

                Section {
                    categoryChips
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                } header: {
                    Text("Category")
                } footer: {
                    Text("Optional. Every account also shows under All.")
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
            .alert("New Category", isPresented: $namingCategory) {
                TextField("Name", text: $newCategory)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    if let name = settings.addCategory(newCategory) {
                        withAnimation(.smooth) { category = name }
                    }
                }
            } message: {
                Text("Name a category to group accounts. It's saved for next time.")
            }
            .sheet(isPresented: $showingScanner) {
                ScannerView { link in
                    showingScanner = false
                    use(link)
                }
            }
        }
    }

    /// The categories as glass chips, like the home screen's; "All" is a filter there, not a choice here.
    /// Tapping the chosen chip again leaves the account uncategorized.
    private var categoryChips: some View {
        GlassEffectContainer(spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(settings.categories(for: vault.accounts).filter { $0 != Account.defaultCategory }, id: \.self) { name in
                    let selected = name == category
                    Button {
                        withAnimation(.smooth) { category = selected ? Account.defaultCategory : name }
                    } label: {
                        HStack(spacing: 6) {
                            if selected {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).transition(.scale.combined(with: .opacity))
                            }
                            Text(name)
                        }
                            .fixedSize()
                            .font(.subheadline.weight(selected ? .semibold : .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                    .glassEffectID(name, in: chips)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Button {
                    newCategory = ""
                    namingCategory = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.caption.weight(.bold))
                        Text("New")
                    }
                    .font(.subheadline.weight(.semibold))
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.accentColor.opacity(0.18)).interactive(), in: .capsule)
                .accessibilityLabel("New Category")
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

/// Lays its children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
