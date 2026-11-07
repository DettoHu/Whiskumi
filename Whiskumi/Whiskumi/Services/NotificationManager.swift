import AppKit
import Observation
import UserNotifications
import os

/// Optional, gentle reminders. Never more than one of a kind every few hours,
/// always phrased kindly, and only when the user switched them on.
@Observable
final class NotificationManager {
    enum Permission { case unknown, allowed, denied }

    private(set) var permission: Permission = .unknown
    private(set) var lastError: String?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let reminderInterval: TimeInterval = 4 * 3600

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        refreshPermission()
    }

    private var center: UNUserNotificationCenter { .current() }

    func refreshPermission() {
        Task { [weak self] in
            guard let center = self?.center else { return }
            let status = await center.notificationSettings().authorizationStatus
            switch status {
            case .authorized, .provisional: self?.permission = .allowed
            case .denied: self?.permission = .denied
            default: self?.permission = .unknown
            }
        }
    }

    /// Called when the user turns notifications on.
    func requestPermission() {
        lastError = nil
        Task { [weak self] in
            guard let center = self?.center else { return }
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                self?.permission = granted ? .allowed : .denied
                if !granted { self?.settings.notificationsEnabled = false }
            } catch {
                self?.permission = .denied
                self?.lastError = error.localizedDescription
                self?.settings.notificationsEnabled = false
            }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Evaluates needs after each tick and sends at most one friendly nudge.
    func evaluate(_ needs: CatNeeds) {
        guard settings.notificationsEnabled, permission == .allowed else { return }
        if settings.feedingReminders, needs.fullness < 0.2 {
            send(id: "feeding", title: "Whiskumi is a little peckish",
                 body: "A small snack would make a certain cat very happy.")
        } else if settings.waterReminders, needs.hydration < 0.2 {
            send(id: "water", title: "Whiskumi could use some water",
                 body: "A fresh bowl of water is always appreciated.")
        }
    }

    private func send(id: String, title: String, body: String) {
        let key = "lastReminder.\(id)"
        let last = defaults.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > reminderInterval else { return }
        defaults.set(Date(), forKey: key)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "whiskumi.\(id)", content: content, trigger: nil)
        let center = self.center
        Task {
            do {
                try await center.add(request)
            } catch {
                Log.app.error("Notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
