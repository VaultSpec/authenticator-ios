import SwiftUI

@main
struct VaultSpecApp: App {
    @State private var vault = VaultStore()
    @State private var cloud = CloudStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vault)
                .environment(cloud)
                .environment(settings)
                #if DEBUG
                .task {
                    await vault.seedDemoIfRequested()
                    DebugOptions.applyOrientation()
                }
                .preferredColorScheme(DebugOptions.colorScheme)
                #endif
        }
    }
}

/// Chooses between setup, lock and the vault, and hides the vault from the app switcher.
struct RootView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(CloudStore.self) private var cloud
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Backdrop()

            switch vault.state {
            case .needsSetup: SetupView().transition(.opacity)
            case .locked: LockView().transition(.opacity)
            case .unlocked: HomeView().transition(.opacity)
            }

            if hidesVault {
                PrivacyCover().transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: vault.state)
        .animation(.easeInOut(duration: 0.2), value: scenePhase)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { vault.lock() }
        }
        // Automatic cloud backup after every change, and a retry of a failed one on unlock
        .onChange(of: vault.revision) {
            cloud.scheduleBackup(vault.accounts)
        }
        .onChange(of: vault.state) { _, state in
            if state == .unlocked, cloud.isPending { cloud.scheduleBackup(vault.accounts) }
        }
        #if targetEnvironment(macCatalyst)
        .task {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.sizeRestrictions?.minimumSize = CGSize(width: 440, height: 600)
            }
        }
        #endif
    }

    private var hidesVault: Bool {
        #if targetEnvironment(macCatalyst)
        // A Mac window goes inactive whenever another app is in front, which is exactly when
        // people paste a code, so only cover it once the window is hidden or minimised.
        scenePhase == .background
        #else
        scenePhase != .active
        #endif
    }
}

/// Covers the screen when the app is inactive so codes don't appear in the app switcher.
private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            LogoMark().frame(width: 72, height: 72)
        }
    }
}

#if DEBUG
/// Launch arguments for screenshots: `-colorScheme dark|light` and `-orientation landscape`.
private enum DebugOptions {
    static func applyOrientation() {
        #if !targetEnvironment(macCatalyst)
        guard UserDefaults.standard.string(forKey: "orientation") == "landscape" else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        #endif
    }

    static var colorScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "colorScheme") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}
#endif
