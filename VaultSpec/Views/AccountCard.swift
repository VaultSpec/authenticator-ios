import SwiftUI

/// One account on Liquid Glass: who it is, the live code, and how long it has left.
struct AccountCard: View {
    let account: Account
    let now: Date
    /// False while Tap to Reveal hides the code.
    var isRevealed = true
    var isHighlighted = false
    /// Keeps the code out of screenshots and recordings.
    var protectsCode = false
    /// Whether tapping (eventually) copies, which decides if the copy glyph shows.
    var tapCopies = true
    var onTap: (String) -> Void
    var onCopy: (String) -> Void
    var onDelete: () -> Void

    private var code: String { TOTP.code(for: account, at: now) }
    private var remaining: Int { TOTP.secondsRemaining(period: account.period, at: now) }

    var body: some View {
        Button {
            onTap(code)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ServiceMonogram(name: account.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.title)
                            .font(.headline)
                            .lineLimit(1)
                        if !account.name.isEmpty, !account.issuer.isEmpty {
                            Text(account.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    CountdownRing(remaining: remaining, period: account.period)
                }

                HStack(alignment: .center) {
                    ScreenshotShield(isActive: protectsCode) {
                        CodeText(text: isRevealed ? TOTP.formatted(code) : hiddenCode, isRevealed: isRevealed, code: code)
                    }
                    .fixedSize()
                    Spacer()
                    if !isRevealed || tapCopies {
                        Image(systemName: isRevealed ? "doc.on.doc" : "eye")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                // Highlight on Tap: drawn in the label so it sits above the glass
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .opacity(isHighlighted ? 1 : 0)
            }
            .contentShape(.rect(cornerRadius: 30))
        }
        .buttonStyle(.plain)
        .glassEffect(
            isHighlighted ? .regular.tint(.accentColor.opacity(0.3)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 30)
        )
        .animation(.smooth(duration: 0.2), value: isHighlighted)
        .contextMenu {
            Button("Copy Code", systemImage: "doc.on.doc") { onCopy(code) }
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isRevealed ? TOTP.formatted(code) : "Hidden")
        .accessibilityHint(accessibilityHint)
    }

    /// Dots in the code's grouping, e.g. "••• •••".
    private var hiddenCode: String {
        TOTP.formatted(String(repeating: "0", count: account.digits)).replacingOccurrences(of: "0", with: "•")
    }

    private var accessibilityHint: String {
        if !isRevealed { return "Shows the code" }
        if isHighlighted { return "Copies the code" }
        return tapCopies ? "Copies the code" : ""
    }
}

/// The large code. Lives inside the screenshot shield's own hosting view.
private struct CodeText: View {
    let text: String
    let isRevealed: Bool
    let code: String

    var body: some View {
        Text(text)
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isRevealed ? .primary : .secondary)
            .contentTransition(.numericText())
            .animation(.snappy, value: code)
            .animation(.smooth, value: isRevealed)
            .lineLimit(1)
    }
}
