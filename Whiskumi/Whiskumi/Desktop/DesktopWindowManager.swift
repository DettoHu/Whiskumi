import AppKit

/// Owns the desktop cat window: its level, Spaces behaviour, size, position and click-through.
/// Positions are expressed as the cat's *feet* in global screen coordinates.
final class DesktopWindowManager {
    let window: DesktopCatWindow
    let catView: DesktopCatView
    let screens: ScreenManager
    let clock = FrameClock()

    private let library: SpriteLibrary
    private var requestedScale: Double = 1
    private var renderQuality: RenderQuality = .pixelPerfect
    private var footInWindow: CGPoint = .zero
    private var backingObserver: NSObjectProtocol?
    private var hasLayout = false

    private(set) var pointsPerPixel: CGFloat = 1
    /// Unrounded feet position; the window itself is snapped to the device pixel grid.
    private(set) var foot: CGPoint = .zero

    /// Keeps mouse events flowing to the cat regardless of the pixel under the cursor (e.g. while dragging).
    var forceInteractive = false {
        didSet { if forceInteractive { window.ignoresMouseEvents = false } }
    }

    init(library: SpriteLibrary, screens: ScreenManager) {
        self.library = library
        self.screens = screens
        window = DesktopCatWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 280))
        catView = DesktopCatView(library: library)
        window.contentView = catView
        window.ignoresMouseEvents = true
        clock.attach(to: catView)
        catView.onFrameDisplayed = { [weak self] in self?.refreshMouseTransparency() }
        backingObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeBackingPropertiesNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recomputeLayout() }
        }
    }

    deinit {
        if let backingObserver { NotificationCenter.default.removeObserver(backingObserver) }
    }

    // MARK: - Settings

    func apply(_ settings: AppSettings) {
        switch settings.windowLayer {
        case .aboveAll: window.level = .floating
        case .normal: window.level = .normal
        case .desktop: window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle, .stationary]
        if settings.showOnAllDesktops {
            behavior.insert(.canJoinAllSpaces)
            behavior.insert(.fullScreenAuxiliary)
        } else {
            behavior.insert(.managed)
        }
        window.collectionBehavior = behavior
        catView.renderQuality = settings.renderQuality
        catView.effectsEnabled = settings.visualEffects
        catView.shadowEnabled = settings.groundShadow
        if !hasLayout || requestedScale != settings.catScale || renderQuality != settings.renderQuality {
            requestedScale = settings.catScale
            renderQuality = settings.renderQuality
            recomputeLayout()
        }
    }

    /// Screen points per art pixel. "Pixel Perfect" snaps to whole device pixels so no art pixel is split.
    private func effectivePointsPerPixel() -> CGFloat {
        let base = CGFloat(requestedScale)
        guard renderQuality == .pixelPerfect else { return base }
        let backing = window.screen?.backingScaleFactor ?? screens.nearestScreen(to: foot)?.backingScaleFactor ?? 2
        let devicePixels = max(1, (base * backing).rounded())
        return devicePixels / backing
    }

    func recomputeLayout() {
        hasLayout = true
        let ppp = effectivePointsPerPixel()
        pointsPerPixel = ppp
        let extents = library.extents
        let width = ceil((extents.horizontal * 2 + 24) * ppp)
        let bottom = ceil((max(extents.down, 4) + 12) * ppp)
        let particleRoom: CGFloat = 56
        let height = ceil((extents.up + particleRoom) * ppp) + bottom
        footInWindow = CGPoint(x: (width / 2).rounded(), y: bottom)
        catView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        catView.pointsPerPixel = ppp
        catView.footPoint = footInWindow
        window.setFrame(NSRect(origin: windowOrigin(for: foot), size: CGSize(width: width, height: height)), display: true)
    }

    // MARK: - Position

    private func windowOrigin(for foot: CGPoint) -> CGPoint {
        let backing = window.backingScaleFactor > 0 ? window.backingScaleFactor : 2
        func snap(_ v: CGFloat) -> CGFloat { (v * backing).rounded() / backing }
        return CGPoint(x: snap(foot.x - footInWindow.x), y: snap(foot.y - footInWindow.y))
    }

    func moveFoot(to point: CGPoint) {
        foot = point
        window.setFrameOrigin(windowOrigin(for: point))
        refreshMouseTransparency()
    }

    /// Re-evaluates click-through when the cat moves or changes pose under a still pointer.
    func refreshMouseTransparency() {
        guard window.isVisible, !forceInteractive else { return }
        let cursor = NSEvent.mouseLocation
        guard window.frame.insetBy(dx: -8, dy: -8).contains(cursor) || !window.ignoresMouseEvents else { return }
        updateMouseTransparency(cursor: cursor)
    }

    /// Horizontal range the feet may use on the screen at `point`, keeping the cat in view.
    func walkableRange(near point: CGPoint) -> ClosedRange<CGFloat> {
        let visible = screens.visibleFrame(near: point)
        let margin = 66 * pointsPerPixel
        let low = visible.minX + margin
        return low...max(low, visible.maxX - margin)
    }

    func verticalRange(near point: CGPoint) -> ClosedRange<CGFloat> {
        let visible = screens.visibleFrame(near: point)
        let top = visible.maxY - 112 * pointsPerPixel
        return visible.minY...max(visible.minY, top)
    }

    func clampedFoot(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x.clamped(to: walkableRange(near: point)), y: point.y.clamped(to: verticalRange(near: point)))
    }

    /// Floor of the screen at `point` (top of the Dock or the bottom edge).
    func floorY(near point: CGPoint) -> CGFloat {
        screens.visibleFrame(near: point).minY
    }

    // MARK: - Visibility

    var isVisible: Bool { window.isVisible }

    func show() {
        if pointsPerPixel <= 0 { recomputeLayout() }
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    // MARK: - Hit testing / click-through

    func isCatPixel(atScreenPoint point: CGPoint, tolerance: Int = 2) -> Bool {
        guard window.isVisible, window.frame.contains(point) else { return false }
        let local = CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        return catView.isCatPixel(at: local, tolerance: tolerance)
    }

    /// Transparent parts of the window let clicks fall through to whatever is underneath.
    func updateMouseTransparency(cursor: CGPoint) {
        let interactive = forceInteractive || isCatPixel(atScreenPoint: cursor)
        if window.ignoresMouseEvents == interactive {
            window.ignoresMouseEvents = !interactive
        }
    }

    /// Head position in screen coordinates (for cursor reactions and anchoring menus).
    var headPoint: CGPoint {
        CGPoint(x: foot.x, y: foot.y + 80 * pointsPerPixel)
    }

    func screenRect(forViewRect rect: CGRect) -> CGRect {
        window.convertToScreen(rect)
    }
}
