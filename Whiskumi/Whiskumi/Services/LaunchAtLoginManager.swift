import Foundation
import Observation
import ServiceManagement

/// Launch at login through `SMAppService`, with the status reflected live in Settings.
@Observable
final class LaunchAtLoginManager {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?

    init() {
        refresh()
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            }
        } catch {
            lastError = "macOS didn't allow this change (\(error.localizedDescription)). You can manage login items in System Settings."
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
