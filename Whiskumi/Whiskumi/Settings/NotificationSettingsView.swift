import SwiftUI

struct NotificationSettingsView: View {
    let settings: AppSettings
    let notifications: NotificationManager

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            Section {
                Toggle(isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { enabled in
                        settings.notificationsEnabled = enabled
                        if enabled, notifications.permission != .allowed { notifications.requestPermission() }
                    }
                )) {
                    Text("Allow notifications")
                    SettingCaption("Off by default. Whiskumi never nags — at most one gentle note every few hours.")
                }
                if notifications.permission == .denied {
                    HStack {
                        SettingCaption("Notifications are turned off for Whiskumi in System Settings.")
                        Spacer()
                        Button("Open Settings…") { notifications.openSystemSettings() }
                    }
                }
                if let error = notifications.lastError {
                    SettingCaption(error)
                }
            }

            Section("Reminders") {
                Toggle("When Whiskumi gets hungry", isOn: $settings.feedingReminders)
                Toggle("When Whiskumi gets thirsty", isOn: $settings.waterReminders)
            }
            .disabled(!settings.notificationsEnabled)
        }
    }
}
