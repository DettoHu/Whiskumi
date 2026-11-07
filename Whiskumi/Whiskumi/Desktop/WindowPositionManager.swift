import AppKit

/// Remembers where Whiskumi sits (feet position, in global screen points) and on which display.
final class WindowPositionManager {
    private struct SavedPosition: Codable {
        var x: Double
        var y: Double
        var displayID: UInt32?
        /// Feet position relative to that display's visible frame (0...1), for when its geometry changes.
        var relativeX: Double?
        var relativeY: Double?
    }

    private let defaults: UserDefaults
    private let screens: ScreenManager
    private let key = "catPosition"
    private var pendingSave: DispatchWorkItem?

    init(screens: ScreenManager, defaults: UserDefaults = .standard) {
        self.screens = screens
        self.defaults = defaults
    }

    /// Debounced, so continuous movement doesn't hammer UserDefaults.
    func save(foot: CGPoint) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow(foot: foot) }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func saveNow(foot: CGPoint) {
        pendingSave?.cancel()
        pendingSave = nil
        var position = SavedPosition(x: foot.x, y: foot.y)
        if let screen = screens.nearestScreen(to: foot) {
            position.displayID = ScreenManager.displayID(of: screen)
            let visible = screen.visibleFrame
            position.relativeX = Double((foot.x - visible.minX) / max(1, visible.width))
            position.relativeY = Double((foot.y - visible.minY) / max(1, visible.height))
        }
        if let data = try? JSONEncoder().encode(position) {
            defaults.set(data, forKey: key)
        }
    }

    /// The saved feet position if its display is still attached, adapted to that display's current geometry.
    func restoredFoot() -> CGPoint? {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode(SavedPosition.self, from: data) else { return nil }
        if let id = saved.displayID, let screen = screens.screen(withDisplayID: id) {
            let visible = screen.visibleFrame
            let point = CGPoint(x: saved.x, y: saved.y)
            if visible.insetBy(dx: -4, dy: -4).contains(point) { return point }
            if let rx = saved.relativeX, let ry = saved.relativeY {
                return CGPoint(x: visible.minX + visible.width * rx, y: visible.minY + visible.height * ry)
            }
        }
        let point = CGPoint(x: saved.x, y: saved.y)
        return screens.isOnSomeScreen(point) ? point : nil
    }

    func defaultFoot(_ position: DefaultPosition) -> CGPoint {
        let visible = screens.primaryScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let inset: CGFloat = 160
        switch position {
        case .bottomLeft: return CGPoint(x: visible.minX + inset, y: visible.minY)
        case .bottomCenter: return CGPoint(x: visible.midX, y: visible.minY)
        case .bottomRight: return CGPoint(x: visible.maxX - inset, y: visible.minY)
        case .center: return CGPoint(x: visible.midX, y: visible.midY - 60)
        }
    }

    func forget() {
        defaults.removeObject(forKey: key)
    }
}
