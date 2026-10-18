import SwiftUI

/// One account on Liquid Glass: who it is, the live code, and how long it has left.
struct AccountCard: View {
    let account: Account
    let now: Date
    var onCopy: (String) -> Void
    var onDelete: () -> Void

    private var code: String { TOTP.code(for: account, at: now) }
    private var remaining: Int { TOTP.secondsRemaining(period: account.period, at: now) }

    var body: some View {
        Button {
            onCopy(code)
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

                HStack(alignment: .lastTextBaseline) {
                    Text(TOTP.formatted(code))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: code)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 30))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30))
        .contextMenu {
            Button("Copy Code", systemImage: "doc.on.doc") { onCopy(code) }
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Copies the code")
    }
}
