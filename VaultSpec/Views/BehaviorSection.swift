import SwiftUI

/// The "Behavior" group in Settings, matching the Android app's options.
struct BehaviorSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section("Behavior") {
            if AppSettings.canBlockScreenshots {
                Toggle(isOn: $settings.allowScreenshots) {
                    row("Allow Screenshots", "When off, codes are blank in screenshots, screen recordings and mirrored screens.", "camera.viewfinder")
                }
            }
            Toggle(isOn: $settings.tapToReveal) {
                row("Tap to Reveal Codes", "Codes are hidden until tapped (\(Int(settings.revealSeconds))s timeout).", "eye")
            }
            Toggle(isOn: $settings.tapToCopy) {
                row("Tap to Copy Code", "Tap an account to copy its code to the clipboard.", "doc.on.doc")
            }
            Toggle(isOn: $settings.highlightOnTap) {
                row("Highlight Account on Tap", "1st tap highlights, 2nd tap copies.", "highlighter")
            }
            Picker(selection: $settings.passwordReminderDays) {
                ForEach(AppSettings.reminderChoices, id: \.self) { Text("\($0) days").tag($0) }
            } label: {
                row("Password Reminder", "Ask for the vault password periodically.", "calendar.badge.clock")
            }
            .pickerStyle(.menu)
        }
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }
}
