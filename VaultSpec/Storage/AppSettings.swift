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
    private(set) var lastPasswordUnlock: Date?

    let revealSeconds: TimeInterval = 30
    /// The screenshot shield relies on iOS's secure text field; it isn't used on the Mac.
    static let canBlockScreenshots = !ProcessInfo.processInfo.isMacCatalystApp
    static let reminderChoices = [7, 15, 30]

    private enum Keys {
        static let allowScreenshots = "behavior.allowScreenshots"
        static let tapToReveal = "behavior.tapToReveal"
        static let tapToCopy = "behavior.tapToCopy"
        static let highlightOnTap = "behavior.highlightOnTap"
        static let reminderDays = "behavior.passwordReminderDays"
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
