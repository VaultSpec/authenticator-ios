import Foundation
import Observation

/// The Behavior settings, shared with the Android app's options and defaults.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    /// When off, codes are blanked in screenshots, screen recordings and mirrored displays.
    var allowScreenshots: Bool { didSet { defaults.set(allowScreenshots, forKey: Keys.allowScreenshots) } }
    /// Codes show as dots until tapped, then hide again after `revealSeconds`.
    var tapToReveal: Bool { didSet { defaults.set(tapToReveal, forKey: Keys.tapToReveal) } }
    var tapToCopy: Bool { didSet { defaults.set(tapToCopy, forKey: Keys.tapToCopy) } }
    /// The first tap highlights a card and the second copies its code.
    var highlightOnTap: Bool { didSet { defaults.set(highlightOnTap, forKey: Keys.highlightOnTap) } }
    /// Face ID / Touch ID stops working after this many days until the vault password is entered.
    var passwordReminderDays: Int { didSet { defaults.set(passwordReminderDays, forKey: Keys.reminderDays) } }
    /// How long the app can be away (in the background, or behind other apps on the Mac) before
    /// the vault locks. 0 locks as soon as it's away.
    var autoLockSeconds: Int { didSet { defaults.set(autoLockSeconds, forKey: Keys.autoLockSeconds) } }
    private(set) var lastPasswordUnlock: Date?

    let revealSeconds: TimeInterval = 30
    /// The screenshot shield relies on iOS's secure text field; it isn't used on the Mac.
    static let canBlockScreenshots = !ProcessInfo.processInfo.isMacCatalystApp
    static let reminderChoices = [7, 15, 30]
    static let autoLockChoices: [(seconds: Int, label: String)] = [
        (0, "Immediately"), (60, "After 1 minute"), (300, "After 5 minutes"),
        (900, "After 15 minutes"), (3600, "After 1 hour"),
    ]
    /// A Mac sits behind other windows all day while people paste codes, so it waits longer by default.
    static let defaultAutoLockSeconds = ProcessInfo.processInfo.isMacCatalystApp ? 300 : 60

    private enum Keys {
        static let allowScreenshots = "behavior.allowScreenshots"
        static let tapToReveal = "behavior.tapToReveal"
        static let tapToCopy = "behavior.tapToCopy"
        static let highlightOnTap = "behavior.highlightOnTap"
        static let reminderDays = "behavior.passwordReminderDays"
        static let autoLockSeconds = "security.autoLockSeconds"
        static let lastPasswordUnlock = "behavior.lastPasswordUnlock"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func flag(_ key: String, default value: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
        }
        allowScreenshots = flag(Keys.allowScreenshots, default: false)
        tapToReveal = flag(Keys.tapToReveal, default: false)
        tapToCopy = flag(Keys.tapToCopy, default: true)
        highlightOnTap = flag(Keys.highlightOnTap, default: false)
        let days = defaults.integer(forKey: Keys.reminderDays)
        passwordReminderDays = Self.reminderChoices.contains(days) ? days : 15
        let lockAfter = defaults.object(forKey: Keys.autoLockSeconds) as? Int
        autoLockSeconds = lockAfter.flatMap { s in Self.autoLockChoices.contains { $0.seconds == s } ? s : nil }
            ?? Self.defaultAutoLockSeconds
        lastPasswordUnlock = defaults.object(forKey: Keys.lastPasswordUnlock) as? Date
    }

    /// Call whenever the vault password is entered (setup, unlock, change, restore).
    func recordPasswordEntry(at date: Date = .now) {
        lastPasswordUnlock = date
        defaults.set(date, forKey: Keys.lastPasswordUnlock)
    }

    func isPasswordReminderDue(at date: Date = .now) -> Bool {
        guard let lastPasswordUnlock else { return false }
        return date.timeIntervalSince(lastPasswordUnlock) > Double(passwordReminderDays) * 86_400
    }
}
