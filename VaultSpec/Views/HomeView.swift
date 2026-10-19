import SwiftUI
import UniformTypeIdentifiers

/// The unlocked vault: search, category filter and a list of glass account cards.
struct HomeView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
    @State private var search = ""
    @State private var category = Account.defaultCategory
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var toast: String?
    @State private var copies = 0
    @State private var pendingDelete: Account?
    /// Tap to Reveal: when each revealed code hides again.
    @State private var revealedUntil: [Account.ID: Date] = [:]
    @State private var highlighted: Account.ID?
    @Namespace private var chips

    private var visibleAccounts: [Account] {
        vault.accounts.filter { account in
            (category == Account.defaultCategory || account.category == category) &&
                (search.isEmpty || account.title.localizedCaseInsensitiveContains(search)
                    || account.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    categoryBar

                    if visibleAccounts.isEmpty {
                        EmptyVault(isFiltering: !search.isEmpty || category != Account.defaultCategory) {
                            showingAdd = true
                        }
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            GlassEffectContainer(spacing: 16) {
                                // Reflows with the width: one column on an iPhone in portrait, two in
                                // landscape, and more on iPad and Mac as the window grows.
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 14)], spacing: 14) {
                                    ForEach(visibleAccounts) { account in
                                        AccountCard(
                                            account: account,
                                            now: timeline.date,
                                            isRevealed: !settings.tapToReveal || (revealedUntil[account.id] ?? .distantPast) > timeline.date,
                                            isHighlighted: highlighted == account.id,
                                            protectsCode: AppSettings.canBlockScreenshots && !settings.allowScreenshots,
                                            tapCopies: settings.tapToCopy || settings.highlightOnTap
                                        ) { code in
                                            tap(account, code: code, now: timeline.date)
                                        } onCopy: { code in
                                            copy(code)
                                        } onDelete: {
                                            pendingDelete = account
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: 1600)
                .frame(maxWidth: .infinity)
            }
            .background { Backdrop() }
            .navigationTitle("VaultSpec")
            .searchable(text: $search, prompt: "Search accounts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Lock", systemImage: "lock") { vault.lock() }
                        .keyboardShortcut("l", modifiers: [.command, .control])
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                        .keyboardShortcut(",")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Account", systemImage: "plus") { showingAdd = true }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut("n")
                }
            }
            .sheet(isPresented: $showingAdd) { AddAccountView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            #if DEBUG
            // `-screen settings|add` opens that sheet on launch, for App Store screenshots
            .task {
                switch UserDefaults.standard.string(forKey: "screen") {
                case "settings": showingSettings = true
                case "add": showingAdd = true
                default: break
                }
            }
            #endif
            .confirmationDialog(
                "Delete \(pendingDelete?.title ?? "account")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDelete { try? vault.delete(pendingDelete) }
                    pendingDelete = nil
                }
            } message: {
                Text("You won't be able to sign in with this account's codes until you add it again.")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Toast(message: toast, symbol: "checkmark.circle.fill")
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: copies)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Account.categories, id: \.self) { name in
                        let selected = name == category
                        Button {
                            withAnimation(.smooth) { category = name }
                        } label: {
                            Text(name)
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
                }
                .padding(.vertical, 4)
            }
        }
        .scrollClipDisabled()
    }

    /// Same order as the Android app: reveal a hidden code, then highlight, then copy.
    private func tap(_ account: Account, code: String, now: Date) {
        if settings.tapToReveal, (revealedUntil[account.id] ?? .distantPast) <= now {
            revealedUntil[account.id] = now.addingTimeInterval(settings.revealSeconds)
            return
        }
        if settings.highlightOnTap {
            if highlighted == account.id {
                highlighted = nil
                copy(code)
            } else {
                highlighted = account.id
            }
            return
        }
        if settings.tapToCopy { copy(code) }
    }

    private func copy(_ code: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: code]],
            options: [.expirationDate: Date.now.addingTimeInterval(60), .localOnly: true]
        )
        copies += 1
        withAnimation(.snappy) { toast = "Copied \(TOTP.formatted(code))" }
        let shown = copies
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if shown == copies { withAnimation(.snappy) { toast = nil } }
        }
    }
}

private struct EmptyVault: View {
    let isFiltering: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isFiltering ? "magnifyingglass" : "shield.lefthalf.filled")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.tint)
            Text(isFiltering ? "No Matches" : "No Accounts Yet")
                .font(.title2.weight(.bold))
            Text(isFiltering ? "Try a different search or category." : "Scan a QR code or enter a setup key to start generating codes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !isFiltering {
                Button("Add Account", systemImage: "plus", action: onAdd)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.top, 24)
    }
}
