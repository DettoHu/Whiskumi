import AppKit
import QuartzCore

/// The yarn ball, lifted from the "play with ball" art and given its own tiny window.
/// It rolls with friction, bounces off screen edges, and can be grabbed and thrown.
final class BallToy {
    let window: TransparentPanel
    private let view: BallView
    private let clock: FrameClock
    private let screens: ScreenManager
    private let imageSize: CGSize

    private(set) var pointsPerPixel: CGFloat
    /// Bottom-centre of the ball in global screen coordinates.
    private(set) var position: CGPoint = .zero
    private(set) var velocity: CGVector = .zero
    /// The ledge the ball rests on (usually the cat's floor).
    var floorY: CGFloat = 0
    private(set) var isHeld = false
    private(set) var lastTouched = Date()
    private var physicsID: UUID?
    private var travelling: Facing = .right

    var onThrown: (() -> Void)?
    var onPoked: (() -> Void)?

    var isMoving: Bool { physicsID != nil }
    var diameter: CGFloat { max(imageSize.width, imageSize.height) * pointsPerPixel }

    init(image: CGImage, clock: FrameClock, screens: ScreenManager, pointsPerPixel: CGFloat, renderQuality: RenderQuality) {
        self.clock = clock
        self.screens = screens
        self.pointsPerPixel = pointsPerPixel
        imageSize = CGSize(width: image.width, height: image.height)
        let side = ceil(max(imageSize.width, imageSize.height) * pointsPerPixel) + 4
        window = TransparentPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side))
        view = BallView(image: image, renderQuality: renderQuality, pointsPerPixel: pointsPerPixel)
        view.frame = NSRect(x: 0, y: 0, width: side, height: side)
        window.contentView = view
        view.toy = self
    }

    func show(matching catWindow: NSWindow) {
        window.level = catWindow.level
        window.collectionBehavior = catWindow.collectionBehavior
        window.alphaValue = 1
        window.order(.above, relativeTo: catWindow.windowNumber)
    }

    func place(at point: CGPoint) {
        stopPhysics()
        position = point
        moveWindow()
    }

    func kick(_ impulse: CGVector) {
        guard !isHeld else { return }
        velocity = impulse
        lastTouched = Date()
        startPhysics()
    }

    func remove(animated: Bool) {
        stopPhysics()
        guard animated else {
            window.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            window.animator().alphaValue = 0
        }, completionHandler: { [window] in
            MainActor.assumeIsolated { window.orderOut(nil) }
        })
    }

    func screensChanged() {
        let visible = screens.visibleFrame(near: position)
        floorY = floorY.clamped(to: visible.minY...max(visible.minY, visible.maxY - diameter))
        place(at: CGPoint(x: position.x.clamped(to: (visible.minX + diameter / 2)...max(visible.minX + diameter / 2, visible.maxX - diameter / 2)),
                          y: max(floorY, position.y.clamped(to: visible.minY...max(visible.minY, visible.maxY - diameter)))))
    }

    // MARK: - Physics

    private func startPhysics() {
        guard physicsID == nil else { return }
        physicsID = clock.add { [weak self] dt in
            guard let self else { return false }
            let alive = self.step(dt)
            if !alive { self.physicsID = nil }
            return alive
        }
    }

    private func stopPhysics() {
        if let physicsID { clock.remove(physicsID) }
        physicsID = nil
    }

    private func step(_ dt: TimeInterval) -> Bool {
        guard !isHeld else { return false }
        let t = CGFloat(dt)
        let gravity: CGFloat = 1700
        velocity.dy -= gravity * t
        position.x += velocity.dx * t
        position.y += velocity.dy * t

        let visible = screens.visibleFrame(near: position)
        let half = diameter / 2
        if position.x - half < visible.minX {
            position.x = visible.minX + half
            velocity.dx = abs(velocity.dx) * 0.55
        } else if position.x + half > visible.maxX {
            position.x = visible.maxX - half
            velocity.dx = -abs(velocity.dx) * 0.55
        }
        if position.y + diameter > visible.maxY {
            position.y = visible.maxY - diameter
            velocity.dy = -abs(velocity.dy) * 0.4
        }
        let floor = max(floorY, visible.minY)
        var grounded = false
        if position.y <= floor {
            position.y = floor
            if velocity.dy < -110 {
                velocity.dy = -velocity.dy * 0.42
            } else {
                velocity.dy = 0
                grounded = true
            }
            velocity.dx *= CGFloat(exp(-2.4 * dt))
        }
        faceTravelDirection()
        moveWindow()
        if grounded && abs(velocity.dx) < 6 {
            velocity = .zero
            return false
        }
        return true
    }

    /// The art draws motion lines trailing the ball; mirror it (losslessly) so they trail its travel.
    private func faceTravelDirection() {
        guard abs(velocity.dx) > 20 else { return }
        let direction: Facing = velocity.dx > 0 ? .right : .left
        if direction != travelling {
            travelling = direction
            view.setMirrored(direction == .left)
        }
    }

    private func moveWindow() {
        let size = window.frame.size
        let backing = window.backingScaleFactor > 0 ? window.backingScaleFactor : 2
        let x = ((position.x - size.width / 2) * backing).rounded() / backing
        let y = ((position.y - 2) * backing).rounded() / backing
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Mouse (from BallView)

    private var grabOffset: CGVector = .zero
    private var dragDistance: CGFloat = 0
    private var dragVelocity: CGVector = .zero
    private var lastDrag: (point: CGPoint, time: TimeInterval)?

    fileprivate func grab(at cursor: CGPoint, time: TimeInterval) {
        stopPhysics()
        isHeld = true
        grabOffset = position - cursor
        dragDistance = 0
        dragVelocity = .zero
        lastDrag = (cursor, time)
        lastTouched = Date()
    }

    fileprivate func drag(to cursor: CGPoint, time: TimeInterval) {
        guard isHeld else { return }
        if let last = lastDrag, time > last.time {
            let dt = time - last.time
            let instant = CGVector(dx: (cursor.x - last.point.x) / dt, dy: (cursor.y - last.point.y) / dt)
            let k = CGFloat(smoothing(rate: 20, dt: dt))
            dragVelocity = CGVector(dx: dragVelocity.dx + (instant.dx - dragVelocity.dx) * k,
                                    dy: dragVelocity.dy + (instant.dy - dragVelocity.dy) * k)
            dragDistance += cursor.distance(to: last.point)
        }
        lastDrag = (cursor, time)
        position = cursor + grabOffset
        moveWindow()
    }

    fileprivate func release(at cursor: CGPoint) {
        guard isHeld else { return }
        isHeld = false
        lastTouched = Date()
        let visible = screens.visibleFrame(near: position)
        if position.y < floorY - 2 { floorY = visible.minY }
        if dragDistance < 3 {
            velocity = CGVector(dx: (Bool.random() ? 1 : -1) * CGFloat.random(in: 140...240), dy: 260)
            startPhysics()
            onPoked?()
        } else {
            let speed = dragVelocity.length
            let limit: CGFloat = 1800
            velocity = speed > limit ? dragVelocity * (limit / speed) : dragVelocity
            startPhysics()
            onThrown?()
        }
    }
}

/// Draws the ball and forwards mouse input to its toy.
final class BallView: NSView {
    weak var toy: BallToy?
    private let ballLayer = CALayer()
    private let image: CGImage
    private let pointsPerPixel: CGFloat

    init(image: CGImage, renderQuality: RenderQuality, pointsPerPixel: CGFloat) {
        self.image = image
        self.pointsPerPixel = pointsPerPixel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
        ballLayer.contents = image
        ballLayer.configureForPixelArt(renderQuality)
        ballLayer.actions = ["transform": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(ballLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        // Same art-pixel scale as the cat, on whole device pixels.
        let grid = PixelGrid(backingScale: window?.backingScaleFactor ?? 2, pointsPerPixel: pointsPerPixel)
        let width = grid.length(CGFloat(image.width))
        let height = grid.length(CGFloat(image.height))
        let originX = grid.snap((bounds.width - width) / 2)
        ballLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        ballLayer.position = CGPoint(x: originX + width / 2, y: 2 + height / 2)
    }

    /// Mirroring about the centre keeps the aligned frame in place.
    func setMirrored(_ mirrored: Bool) {
        ballLayer.setAffineTransform(mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { toy?.grab(at: NSEvent.mouseLocation, time: event.timestamp) }
    override func mouseDragged(with event: NSEvent) { toy?.drag(to: NSEvent.mouseLocation, time: event.timestamp) }
    override func mouseUp(with event: NSEvent) { toy?.release(at: NSEvent.mouseLocation) }
}
