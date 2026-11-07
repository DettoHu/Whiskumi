import AppKit

/// Screen geometry helpers and display-change notifications.
final class ScreenManager {
    var onScreensChanged: (() -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onScreensChanged?() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var screens: [NSScreen] { NSScreen.screens }

    var primaryScreen: NSScreen? { NSScreen.screens.first ?? NSScreen.main }

    func screen(containing point: CGPoint) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
    }

    /// The screen containing `point`, or the closest one when the point is off every screen.
    func nearestScreen(to point: CGPoint) -> NSScreen? {
        if let hit = screen(containing: point) { return hit }
        return screens.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    func visibleFrame(near point: CGPoint) -> CGRect {
        nearestScreen(to: point)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        screens.first { Self.displayID(of: $0) == id }
    }

    /// Is any part of the visible area within `inset` of the point?
    func isOnSomeScreen(_ point: CGPoint) -> Bool {
        screens.contains { $0.visibleFrame.insetBy(dx: -2, dy: -2).contains(point) }
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
