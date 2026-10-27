import AVFoundation
import SwiftUI

// Scan & Connect: a signed-in device shows a cloud of fine specks, like Apple's Quick Start, and a new
// device scans it through a round camera frame. The cloud is a PairingCode: its centre, ring and data
// dots are dense clusters of specks inside a lighter haze, so it reads as one soft sphere. The new device
// then enters the vault password, which opens the snapshot the code points to (CloudStore.claimPairing).

/// The pairing cloud. With a [token] its specks carry the code; without one it's the same cloud with
/// nothing encoded, for the "connecting" moments. When [burstAt] is set the cloud flies apart and fades.
struct ParticleCloud: View {
    var token: String?
    var burstAt: Date?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let code = PairingCodeArt.codeLayer(token: token, pixels: Int(side * displayScale), dark: colorScheme == .dark)
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let burst = burstAt.map { min(max(timeline.date.timeIntervalSince($0) / 0.9, 0), 1) } ?? 0
                let eased = 1 - pow(1 - burst, 3)
                ZStack {
                    // A soft glow for volume, a ball of particles turning in 3D, and the code: a flat layer
                    // facing the viewer inside the ball, so a camera always sees it straight on
                    Image("PairingCloud")
                        .resizable()
                        .scaleEffect(1 + 0.015 * sin(t * 0.9))
                    Canvas { context, size in
                        PairingCodeArt.drawSphere(in: &context, size: size, dark: colorScheme == .dark, time: t)
                    }
                    Image(decorative: code, scale: displayScale)
                        .resizable()
                        .rotationEffect(.radians(t * 0.06))
                    Canvas { context, size in
                        PairingCodeArt.drawSparkles(in: &context, size: size, dark: colorScheme == .dark, time: t)
                    }
                }
                .frame(width: side, height: side)
                .scaleEffect(1 + eased * 0.9)
                .opacity(1 - burst)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityLabel(token == nil ? "Connecting" : "Pairing code")
    }
}

/// Lays out and renders the cloud; shared by the view and the decoder tests.
///
/// Every speck is drawn from the same few blues whether it belongs to the code or to the haze, so
/// colour gives nothing away: the code is only where the specks are denser. A camera, which blurs,
/// sees that density as shapes; the eye sees a soft, grainy sphere.
enum PairingCodeArt {
    /// R, the reference ring's radius, as a fraction of half the image: inside the artwork's solid body.
    static let scale = 0.5
    /// A speck's size, in R.
    static let speckSize = 0.009
    /// Specks per R² inside the code's shapes and, at its fullest, in the haze.
    static let codeDensity = 1.15 / (speckSize * speckSize)
    static let hazeDensity = 0.42 / (speckSize * speckSize)

    /// Speck colours. The same deep blues in dark mode too: the specks sit on the bright glow either way.
    static func palette(dark: Bool) -> [CGColor] {
        [(0.18, 0.45, 0.92), (0.3, 0.58, 0.97), (0.45, 0.68, 1.0)].map { CGColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 0.8) }
    }

    @MainActor private static var cache: [String: CGImage] = [:]

    @MainActor static func codeLayer(token: String?, pixels: Int, dark: Bool) -> CGImage {
        let key = "\(token ?? "")|\(pixels)|\(dark)"
        if let cached = cache[key] { return cached }
        let made = render(code: PairingCode.dots(token: token ?? ""), haze: false, pixels: pixels, dark: dark)
        cache[key] = made
        return made
    }

    // MARK: The 3D ball

    /// Points filling a ball of radius 1.3 (in R), most of them toward its surface so it reads as a sphere.
    static let ball: [(x: Double, y: Double, z: Double, tone: Int)] = {
        var rng = SeededGenerator(seed: 41)
        return (0..<6500).map { i in
            // Uniform direction, radius weighted toward the shell
            let z = Double.random(in: -1...1, using: &rng), a = Double.random(in: 0..<(2 * .pi), using: &rng)
            let ring = (1 - z * z).squareRoot()
            let r = 1.3 * pow(Double.random(in: 0.02...1, using: &rng), i % 4 == 0 ? 0.33 : 0.08)
            return (r * ring * cos(a), r * ring * sin(a), r * z, Int.random(in: 0..<3, using: &rng))
        }
    }()

    /// The ball at [time], turning about a tilted axis, in perspective: (x, y in R; scale; depth 0 back...1 front).
    static func projectedBall(time: Double) -> [(x: Double, y: Double, scale: Double, depth: Double, tone: Int)] {
        let spin = time * 0.42, tilt = 0.38
        let (cs, ss, ct, st) = (cos(spin), sin(spin), cos(tilt), sin(tilt))
        let focal = 3.4
        return ball.map { p in
            let x1 = p.x * cs + p.z * ss, z1 = -p.x * ss + p.z * cs
            let y2 = p.y * ct - z1 * st, z2 = p.y * st + z1 * ct
            let k = focal / (focal - z2)
            return (x1 * k, y2 * k, k, (z2 + 1.3) / 2.6, p.tone)
        }
    }

    /// Draws the ball into a SwiftUI canvas: nearer particles larger and brighter, batched by depth.
    static func drawSphere(in context: inout GraphicsContext, size: CGSize, dark: Bool, time: Double) {
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) / 2 * scale
        let colors = palette(dark: dark).map { Color(cgColor: $0) }
        var layers = Array(repeating: Path(), count: 9) // 3 depths x 3 tones
        for p in projectedBall(time: time) {
            let s = max(0.8, R * 0.009 * p.scale * (0.7 + 0.6 * p.depth))
            let band = min(2, Int(p.depth * 3))
            layers[band * 3 + p.tone].addRect(CGRect(x: mid.x + R * p.x - s / 2, y: mid.y + R * p.y - s / 2, width: s, height: s))
        }
        for band in 0..<3 {
            for tone in 0..<3 {
                context.fill(layers[band * 3 + tone], with: .color(colors[tone].opacity([0.35, 0.6, 0.9][band])))
            }
        }
    }

    /// The same ball drawn into a CoreGraphics context (y-down), for the decoder tests.
    static func drawSphere(into ctx: CGContext, pixels: Int, dark: Bool, time: Double) {
        let half = Double(pixels) / 2, R = half * scale
        let colors = palette(dark: dark)
        for p in projectedBall(time: time).sorted(by: { $0.depth < $1.depth }) {
            let s = max(0.8, R * 0.009 * p.scale * (0.7 + 0.6 * p.depth))
            ctx.setFillColor(colors[p.tone].copy(alpha: [0.35, 0.6, 0.9][min(2, Int(p.depth * 3))])!)
            ctx.fill(CGRect(x: half + R * p.x - s / 2, y: half - R * p.y - s / 2, width: s, height: s))
        }
    }

    /// The whole cloud flattened into one image on a plain background, as a camera would see it.
    static func composite(token: String, pixels: Int, dark: Bool, codeRotation: Double, hazeRotation: Double) -> CGImage {
        let ctx = context(pixels)
        ctx.setFillColor(dark ? CGColor(srgbRed: 0.02, green: 0.03, blue: 0.08, alpha: 1) : CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        ctx.draw(UIImage(named: "PairingCloud")!.cgImage!, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        drawSphere(into: ctx, pixels: pixels, dark: dark, time: hazeRotation)
        for (image, angle) in [(render(code: PairingCode.dots(token: token), haze: false, pixels: pixels, dark: dark), codeRotation)] {
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2)
            ctx.rotate(by: -angle) // CoreGraphics is y-up; this turns clockwise on screen like rotationEffect
            ctx.translateBy(x: -CGFloat(pixels) / 2, y: -CGFloat(pixels) / 2)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            ctx.restoreGState()
        }
        return ctx.makeImage()!
    }

    private static func context(_ pixels: Int) -> CGContext {
        CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Either the code's specks ([code] dots) or the haze, on a transparent image [pixels] wide.
    static func render(code dots: [PairingCode.Dot]?, haze: Bool, pixels: Int, dark: Bool) -> CGImage {
        let ctx = context(pixels)
        // Draw in y-down coordinates so angles match the decoder's
        ctx.translateBy(x: 0, y: CGFloat(pixels))
        ctx.scaleBy(x: 1, y: -1)
        let half = Double(pixels) / 2
        let R = half * scale
        let s = max(1, R * speckSize)
        let colors = palette(dark: dark)
        var rng = SeededGenerator(seed: haze ? 31 : 17)

        func speck(_ x: Double, _ y: Double) {
            ctx.setFillColor(colors[Int.random(in: 0..<colors.count, using: &rng)])
            ctx.fill(CGRect(x: half + R * x - s / 2, y: half + R * y - s / 2, width: s, height: s))
        }
        func fillDisk(cx: Double, cy: Double, radius: Double, density: Double) {
            for _ in 0..<Int(.pi * radius * radius * density) {
                let d = radius * Double.random(in: 0...1, using: &rng).squareRoot(), t = Double.random(in: 0..<(2 * .pi), using: &rng)
                speck(cx + d * cos(t), cy + d * sin(t))
            }
        }

        if haze {
            // Even through the middle, thinning past the ring into a soft edge
            let outer = 1.45
            for _ in 0..<Int(.pi * outer * outer * hazeDensity) {
                let r = outer * Double.random(in: 0...1, using: &rng).squareRoot(), a = Double.random(in: 0..<(2 * .pi), using: &rng)
                guard Double.random(in: 0...1, using: &rng) < exp(-pow(max(0, r - 0.8) / 0.3, 2)) else { continue }
                speck(r * cos(a), r * sin(a))
            }
        }
        if let dots {
            fillDisk(cx: 0, cy: 0, radius: PairingCode.centerRadius, density: codeDensity)
            let ringCount = Int(2 * .pi * PairingCode.ringWidth * codeDensity)
            var made = 0
            while made < ringCount {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                guard abs(remainder(a, 2 * .pi)) > PairingCode.gap / 2 else { continue }
                let r = 1 + PairingCode.ringWidth * Double.random(in: -0.5...0.5, using: &rng)
                speck(r * cos(a), r * sin(a))
                made += 1
            }
            for dot in dots where dot.on {
                fillDisk(cx: dot.radius * cos(dot.angle), cy: dot.radius * sin(dot.angle), radius: PairingCode.dotDiameter / 2, density: codeDensity)
            }
        }
        return ctx.makeImage()!
    }

    /// A few hundred specks that twinkle over the cloud, so it shimmers like Apple's.
    static func drawSparkles(in context: inout GraphicsContext, size: CGSize, dark: Bool, time: Double) {
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) / 2 * scale
        let s = max(1, R * speckSize * 1.4)
        let color = dark ? Color(red: 0.9, green: 0.95, blue: 1) : Color(red: 0.2, green: 0.5, blue: 0.98)
        var rng = SeededGenerator(seed: 5)
        var bright = Path(), dim = Path()
        for _ in 0..<360 {
            let r = 1.35 * Double.random(in: 0...1, using: &rng).squareRoot()
            let a = Double.random(in: 0..<(2 * .pi), using: &rng) + time * Double.random(in: -0.12...0.12, using: &rng)
            let phase = Double.random(in: 0..<(2 * .pi), using: &rng)
            let rect = CGRect(x: mid.x + R * r * cos(a) - s / 2, y: mid.y + R * r * sin(a) - s / 2, width: s, height: s)
            if sin(time * 2.4 + phase) > 0.3 { bright.addRect(rect) } else { dim.addRect(rect) }
        }
        context.fill(bright, with: .color(color.opacity(0.75)))
        context.fill(dim, with: .color(color.opacity(0.25)))
    }
}

/// Deterministic randomness, so the cloud's layout doesn't jump between redraws.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Showing the code (the device that already has the vault)

/// Settings → Connect a Device: shows a pairing code until a new device scans it.
struct ShowPairingCodeView: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case password, starting, showing(id: String, code: String, expires: Date), expired, connected

        var isShowing: Bool { if case .showing = self { true } else { false } }
    }

    @State private var stage = Stage.starting
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @State private var connectedAt: Date?
    /// The token on screen, kept after it's claimed so the cloud can burst.
    @State private var shownToken: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    switch stage {
                    case .password: passwordStep
                    default: orbStep
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Connect a Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: stage == .connected ? .confirmationAction : .cancellationAction) {
                    if stage == .connected {
                        Button("Done", systemImage: "checkmark") { dismiss() }
                    } else {
                        Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: connectedAt)
            .task {
                #if DEBUG
                // `-pairingPreview YES`: a fake code that a "new device" scans after a few seconds, no server
                if UserDefaults.standard.bool(forKey: "pairingPreview") {
                    shownToken = "q1w2e3r4t5y6u7i8"
                    stage = .showing(id: "preview", code: CloudStore.pairingPrefix + "q1w2e3r4t5y6u7i8", expires: .now.addingTimeInterval(300))
                    try? await Task.sleep(for: .seconds(6))
                    stage = .connected
                    connectedAt = .now
                    return
                }
                #endif
                if cloud.hasBackupKey { await start(password: nil) } else { stage = .password }
            }
            .onDisappear {
                if case .showing(let id, _, _) = stage { Task { await cloud.cancelPairing(id: id) } }
            }
        }
    }

    private var passwordStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.tint)
            Text("Enter your vault password to create a code for your new device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SecureField("Vault password", text: $password)
                .textContentType(.password)
                .onSubmit(confirmPassword)
                .padding(18)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            Button(action: confirmPassword) {
                Group { if working { ProgressView() } else { Text("Continue").fontWeight(.semibold) } }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(password.isEmpty || working)
        }
    }

    private var orbStep: some View {
        VStack(spacing: 22) {
            ZStack {
                if let token = shownToken, stage == .connected || stage.isShowing {
                    ParticleCloud(token: token, burstAt: connectedAt)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                Group {
                    switch stage {
                    case .showing: EmptyView()
                    case .connected:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 96, weight: .semibold))
                            .foregroundStyle(.white, Color.accentColor)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    case .expired:
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 64, weight: .medium))
                            .foregroundStyle(.secondary)
                    default:
                        ProgressView().controlSize(.large)
                    }
                }
                .animation(.spring(duration: 0.5, bounce: 0.35).delay(stage == .connected ? 0.45 : 0), value: stage)
            }
            .frame(width: 330, height: 330)

            VStack(spacing: 8) {
                Text(title).font(.title2.weight(.bold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if case .showing(_, _, let expires) = stage {
                    Text(timerInterval: Date.now...expires, countsDown: true)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            if stage == .expired {
                Button("Show a New Code", systemImage: "arrow.clockwise") { Task { await start(password: nil) } }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        }
        .task(id: stage) { await watch() }
    }

    private var title: String {
        switch stage {
        case .connected: "Connected"
        case .expired: "Code Expired"
        default: "Waiting for Other Device…"
        }
    }

    private var message: String {
        switch stage {
        case .connected: "Your new device has your vault. Enter your vault password there to finish."
        case .expired: "For your security, codes last 5 minutes and work once."
        default: "On your new device, open VaultSpec and tap Use Another Device. Then position this image in the frame of its camera."
        }
    }

    private func confirmPassword() {
        guard !password.isEmpty, !working else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            guard await vault.verifyPassword(password) else {
                error = VaultStore.VaultError.wrongPassword.localizedDescription
                return
            }
            await start(password: password)
        }
    }

    private func start(password: String?) async {
        error = nil
        stage = .starting
        do {
            let pairing = try await cloud.startPairing(accounts: vault.accounts, vaultPassword: password ?? (self.password.isEmpty ? nil : self.password))
            shownToken = String(pairing.code.dropFirst(CloudStore.pairingPrefix.count))
            stage = .showing(id: pairing.id, code: pairing.code, expires: .now.addingTimeInterval(5 * 60))
        } catch {
            self.error = error.localizedDescription
            stage = cloud.hasBackupKey || !self.password.isEmpty ? .expired : .password
        }
    }

    /// Polls the server while the code is on screen.
    private func watch() async {
        guard case .showing(let id, _, let expires) = stage, id != "preview" else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if Date.now >= expires {
                stage = .expired
                return
            }
            switch try? await cloud.pairingStatus(id: id) {
            case "claimed":
                stage = .connected
                connectedAt = .now
                return
            case "expired":
                stage = .expired
                return
            default: continue
            }
        }
    }
}

// MARK: - Scanning the code (the new device)

/// Setup → Use Another Device: scan the code, then unlock the vault it brings with the vault password.
struct ScanToConnectView: View {
    /// Receives the opened vault; the presenter creates the vault after this sheet closes.
    let onConnected: (RestoredBackup) -> Void

    @Environment(CloudStore.self) private var cloud
    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case scanning, connecting, password
    }

    @State private var stage = Stage.scanning
    @State private var payload: BackupPayload?
    @State private var scannedAt: Date?
    @State private var password = ""
    @State private var enableBiometrics = true
    @State private var working = false
    @State private var error: String?

    static var isSupported: Bool {
        #if DEBUG
        // `-pairingPreview YES` shows the flow on the simulator, which has no camera
        if UserDefaults.standard.bool(forKey: "pairingPreview") { return true }
        #endif
        return PairingScanner.isSupported
    }

    private var cameraAllowed: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return PairingScanner.isSupported && status != .denied && status != .restricted
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if stage == .scanning {
                    viewfinder.transition(.opacity)
                } else {
                    unlockStep.transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.45), value: stage)
            .navigationTitle(stage == .scanning ? "" : "Use Another Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: scannedAt)
            #if DEBUG
            .task {
                guard UserDefaults.standard.bool(forKey: "pairingPreview") else { return }
                try? await Task.sleep(for: .seconds(4))
                stage = .connecting
                // A sample vault under the demo password (demo-vault-1), as if the other device sent it
                let samples = [("GitHub", "alex-dev"), ("Google", "alex@example.com"), ("AWS", "alex@northwind.io"), ("Proton", "alex@proton.me")]
                    .map { Account(issuer: $0.0, name: $0.1, secret: Base32.encode(VaultCrypto.randomBytes(20)), category: "Personal") }
                payload = try? await Task.detached {
                    try BackupFormat.encrypt(samples, with: BackupFormat.deriveKey(password: "demo-vault-1"))
                }.value
                try? await Task.sleep(for: .seconds(1))
                scannedAt = .now
                stage = .password
            }
            #endif
        }
    }

    // The camera behind a dimmed screen with a round window, ringed by the orbiting particles
    private var viewfinder: some View {
        GeometryReader { proxy in
            let hole = min(proxy.size.width - 64, 300)
            ZStack {
                Color.black
                if cameraAllowed {
                    PairingScanner { claim(CloudStore.pairingPrefix + $0) }
                }

                Rectangle()
                    .fill(.black.opacity(0.62))
                    .overlay {
                        Circle().frame(width: hole, height: hole).blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .allowsHitTesting(false)

                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: hole, height: hole)
                    .allowsHitTesting(false)

                VStack(spacing: 8) {
                    Spacer()
                    Text("Hold Your Other Device Here").font(.title2.weight(.bold))
                    Text(cameraAllowed
                        ? "On your other device, open Settings → Connect a Device. Then center the cloud it shows in the circle."
                        : "Scanning needs the camera. Allow camera access for VaultSpec in Settings.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                    if let error {
                        Text(error).font(.footnote.weight(.semibold)).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .ignoresSafeArea()
        }
    }

    private var unlockStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    ParticleCloud(token: nil, burstAt: stage == .password ? scannedAt : nil)
                    Group {
                        if stage == .password {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 76, weight: .semibold))
                                .foregroundStyle(.white, Color.accentColor)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        } else {
                            ProgressView().controlSize(.large)
                        }
                    }
                    .animation(.spring(duration: 0.5, bounce: 0.35).delay(stage == .password ? 0.45 : 0), value: stage)
                }
                .frame(width: 240, height: 240)

                VStack(spacing: 8) {
                    Text(stage == .password ? "Connected" : "Connecting…").font(.title2.weight(.bold))
                    Text(stage == .password
                        ? "Enter the vault password from your other device. It becomes this device's vault password."
                        : "Getting your vault from your other device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if stage == .password {
                    VStack(spacing: 14) {
                        SecureField("Vault password", text: $password)
                            .textContentType(.password)
                            .onSubmit(unlock)
                            .padding(18)
                            .glassEffect(.regular, in: .rect(cornerRadius: 24))
                        if let biometry = vault.biometryName {
                            Toggle(isOn: $enableBiometrics) {
                                Label("Unlock with \(biometry)", systemImage: vault.biometrySymbol)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .glassEffect(.regular, in: .rect(cornerRadius: 24))
                        }
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                        Button(action: unlock) {
                            Group { if working { ProgressView() } else { Text("Open Vault").fontWeight(.semibold) } }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(password.isEmpty || working)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
    }

    private func claim(_ code: String) {
        guard stage == .scanning else { return }
        error = nil
        stage = .connecting
        Task {
            do {
                let received = try await cloud.claimPairing(code: code)
                payload = received
                scannedAt = .now
                withAnimation(.smooth) { stage = .password }
            } catch {
                self.error = error.localizedDescription
                stage = .scanning
            }
        }
    }

    private func unlock() {
        guard let payload, !password.isEmpty, !working else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                let accounts = try await cloud.decrypt(payload, vaultPassword: password)
                // Like a cloud restore: close first and let the presenter create the vault
                onConnected(RestoredBackup(
                    accounts: accounts, password: password,
                    enableBiometrics: enableBiometrics && vault.biometryName != nil
                ))
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
