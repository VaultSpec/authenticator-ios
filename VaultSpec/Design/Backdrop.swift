import SwiftUI

/// Slowly drifting colour field behind every screen. Liquid Glass needs something rich
/// underneath to refract, so this is part of the design rather than decoration.
struct Backdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: points(at: t),
                colors: colorScheme == .dark ? Self.darkColors : Self.lightColors
            )
        }
        .ignoresSafeArea()
    }

    private func points(at t: Double) -> [SIMD2<Float>] {
        func wave(_ speed: Double, _ phase: Double, _ amount: Float) -> Float {
            Float(sin(t * speed + phase)) * amount
        }
        return [
            [0, 0], [0.5 + wave(0.21, 0, 0.18), 0], [1, 0],
            [0, 0.5 + wave(0.17, 1, 0.15)],
            [0.5 + wave(0.23, 2, 0.2), 0.5 + wave(0.19, 3, 0.2)],
            [1, 0.5 + wave(0.13, 4, 0.15)],
            [0, 1], [0.5 + wave(0.15, 5, 0.18), 1], [1, 1],
        ]
    }

    private static let darkColors: [Color] = [
        Color(red: 0.03, green: 0.05, blue: 0.14), Color(red: 0.06, green: 0.16, blue: 0.42), Color(red: 0.02, green: 0.04, blue: 0.12),
        Color(red: 0.15, green: 0.08, blue: 0.38), Color(red: 0.0, green: 0.36, blue: 0.82), Color(red: 0.02, green: 0.22, blue: 0.36),
        Color(red: 0.02, green: 0.03, blue: 0.09), Color(red: 0.05, green: 0.12, blue: 0.3), Color(red: 0.12, green: 0.04, blue: 0.24),
    ]

    private static let lightColors: [Color] = [
        Color(red: 0.86, green: 0.91, blue: 1.0), Color(red: 0.62, green: 0.78, blue: 1.0), Color(red: 0.9, green: 0.88, blue: 1.0),
        Color(red: 0.78, green: 0.72, blue: 1.0), Color(red: 0.36, green: 0.6, blue: 1.0), Color(red: 0.66, green: 0.9, blue: 0.98),
        Color(red: 0.93, green: 0.95, blue: 1.0), Color(red: 0.7, green: 0.82, blue: 1.0), Color(red: 0.88, green: 0.84, blue: 1.0),
    ]
}
