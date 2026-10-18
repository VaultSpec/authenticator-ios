import SwiftUI

/// The VaultSpec mark: twelve rounded bars, same geometry as the Android app and website.
struct LogoMark: View {
    var body: some View {
        Canvas { context, size in
            let bars: [(Double, Double)] = [
                (21, 34), (27, 42), (33, 52), (39, 62), (45, 72), (51, 78),
                (57, 78), (63, 72), (69, 62), (75, 52), (81, 42), (87, 34),
            ]
            let scale = min(size.width, size.height) / 84
            let origin = CGPoint(x: (size.width - 84 * scale) / 2 - 12 * scale, y: (size.height - 88 * scale) / 2 - 10 * scale)
            for (cx, height) in bars {
                let rect = CGRect(
                    x: origin.x + (cx - 2) * scale, y: origin.y + (54 - height / 2) * scale,
                    width: 4 * scale, height: height * scale
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 2 * scale), with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Rounded tile with the service's initial, coloured consistently from its name.
struct ServiceMonogram: View {
    let name: String
    var size: CGFloat = 46

    var body: some View {
        let hue = Double(abs(name.lowercased().hashValueStable) % 360) / 360
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hue: hue, saturation: 0.62, brightness: 0.95), Color(hue: hue, saturation: 0.78, brightness: 0.72)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private extension String {
    /// Stable across launches (Swift's hashValue is randomised per process).
    var hashValueStable: Int {
        unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    }
}

/// Ring that empties as the current code ages; turns orange then red near the end.
struct CountdownRing: View {
    let remaining: Int
    let period: Int
    var size: CGFloat = 40

    private var tint: Color {
        switch remaining {
        case ...5: .red
        case ...10: .orange
        default: .accentColor
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.28), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: CGFloat(remaining) / CGFloat(period))
                .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            Text("\(remaining)")
                .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText(countsDown: true))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(remaining) seconds left")
    }
}

/// Glass capsule shown briefly at the bottom of the screen.
struct Toast: View {
    let message: String
    let symbol: String

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Lays its children out side by side when the screen is short and wide (an iPhone turned to
/// landscape) and stacked otherwise. Rotating animates between the two.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var spacing: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        let layout = verticalSizeClass == .compact
            ? AnyLayout(HStackLayout(alignment: .center, spacing: spacing * 1.5))
            : AnyLayout(VStackLayout(spacing: spacing))
        layout { content }
            .animation(.smooth, value: verticalSizeClass)
    }
}

/// Centres short content vertically and scrolls it when the screen is too short.
struct CenteredScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content.frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
