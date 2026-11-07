import AppKit
import QuartzCore

protocol DesktopCatViewDelegate: AnyObject {
    func catView(_ view: DesktopCatView, mouseDown event: NSEvent)
    func catView(_ view: DesktopCatView, mouseDragged event: NSEvent)
    func catView(_ view: DesktopCatView, mouseUp event: NSEvent)
    func catView(_ view: DesktopCatView, rightMouseDown event: NSEvent)
    func catView(_ view: DesktopCatView, mouseMoved event: NSEvent)
    func catViewMouseExited(_ view: DesktopCatView)
}

/// Renders Whiskumi with Core Animation layers: the sprite itself, effect sprites
/// lifted from the art (hearts, Zs, "?"), and a small pixel shadow. Pixel art is
/// drawn with nearest-neighbour filtering so it stays crisp on Retina displays.
final class DesktopCatView: NSView, CatRenderer {
    weak var delegate: DesktopCatViewDelegate?
    let library: SpriteLibrary
    /// Called after each new frame is shown (used to keep click-through accurate).
    var onFrameDisplayed: (() -> Void)?

    /// Screen points per source pixel.
    var pointsPerPixel: CGFloat = 1 { didSet { redisplay() } }
    var renderQuality: RenderQuality = .pixelPerfect { didSet { applyFilters() } }
    var effectsEnabled = true { didSet { if !effectsEnabled { clearEmotes() } } }
    var shadowEnabled = true { didSet { updateShadow() } }

    /// Where the cat's feet (anchor) sit, in view coordinates.
    var footPoint: CGPoint = .zero { didSet { redisplay() } }

    /// Visual lift of the sprite above its feet position (carrying, hopping).
    var lift: CGFloat = 0 { didSet { positionSprite(); updateShadow() } }

    private let spriteLayer = CALayer()
    private let shadowLayer = CALayer()
    private let emoteLayer = CALayer()
    private let particleLayer = CALayer()
    private var emoteSublayers: [CALayer] = []
    private var framePropSublayers: [CALayer] = []
    private var trackingArea: NSTrackingArea?

    private(set) var currentData: SpriteAnimationData?
    private(set) var currentFrameIndex = 0
    private(set) var currentFacing: Facing = .right

    init(library: SpriteLibrary) {
        self.library = library
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let root = layer else { return }
        root.backgroundColor = .clear
        root.masksToBounds = false
        for sub in [shadowLayer, spriteLayer, emoteLayer, particleLayer] {
            sub.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "transform": NSNull(), "anchorPoint": NSNull()]
            root.addSublayer(sub)
        }
        shadowLayer.contents = Self.makeShadowImage()
        shadowLayer.opacity = 0
        applyFilters()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sub in [spriteLayer, shadowLayer, emoteLayer, particleLayer] { sub.contentsScale = scale }
    }

    // MARK: - CatRenderer

    func display(_ animation: SpriteAnimationData, frame: Int, facing: Facing, showEmotes: Bool) {
        let poseChanged = currentData !== animation
        currentData = animation
        currentFrameIndex = frame
        currentFacing = facing
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.contents = animation.frame(at: frame).image
        layoutSprite()
        if poseChanged || showEmotes { clearEmotes() }
        if showEmotes && effectsEnabled { presentEmotes(for: animation) }
        updateFrameProps(for: animation, frame: frame)
        CATransaction.commit()
        onFrameDisplayed?()
    }

    private func redisplay() {
        guard currentData != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutSprite()
        CATransaction.commit()
    }

    private var isFlippedHorizontally: Bool {
        guard let data = currentData else { return false }
        return currentFacing != data.facing
    }

    private func layoutSprite() {
        guard let data = currentData else { return }
        let ppp = pointsPerPixel
        spriteLayer.bounds = CGRect(x: 0, y: 0, width: data.size.width * ppp, height: data.size.height * ppp)
        spriteLayer.anchorPoint = CGPoint(x: data.anchor.x / data.size.width, y: 1 - data.anchor.y / data.size.height)
        spriteLayer.setAffineTransform(isFlippedHorizontally ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        positionSprite()
        updateShadow()
    }

    private func positionSprite() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.position = CGPoint(x: footPoint.x, y: footPoint.y + lift)
        emoteLayer.frame = bounds
        emoteLayer.setAffineTransform(CGAffineTransform(translationX: 0, y: lift))
        particleLayer.frame = bounds
        CATransaction.commit()
    }

    private func applyFilters() {
        let filter: CALayerContentsFilter = renderQuality == .smooth ? .linear : .nearest
        for sub in [spriteLayer, shadowLayer] {
            sub.magnificationFilter = filter
            sub.minificationFilter = renderQuality == .smooth ? .trilinear : .nearest
        }
        for sub in emoteSublayers { sub.magnificationFilter = filter }
    }

    // MARK: - Emotes and particles

    private func clearEmotes() {
        for sub in emoteSublayers { sub.removeFromSuperlayer() }
        emoteSublayers.removeAll()
    }

    /// Effects drawn in the source art, placed exactly where the artist put them, with a little pop.
    private func presentEmotes(for data: SpriteAnimationData) {
        for (i, placement) in data.emotes.enumerated() {
            guard let image = library.prop(placement.prop) else { continue }
            let frame = propFrame(origin: placement.origin, size: CGSize(width: image.width, height: image.height), in: data)
            let sub = makeSpriteLayer(image: image, frame: frame)
            emoteLayer.addSublayer(sub)
            emoteSublayers.append(sub)
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.2, 1.18, 0.95, 1.0]
            pop.keyTimes = [0, 0.55, 0.8, 1]
            pop.duration = 0.32
            pop.beginTime = CACurrentMediaTime() + Double(i) * 0.08
            pop.fillMode = .backwards
            sub.add(pop, forKey: "pop")
            let bob = CABasicAnimation(keyPath: "position.y")
            bob.byValue = 2 * pointsPerPixel
            bob.duration = 0.6
            bob.autoreverses = true
            bob.repeatCount = .infinity
            bob.beginTime = CACurrentMediaTime() + 0.35 + Double(i) * 0.15
            bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sub.add(bob, forKey: "bob")
        }
    }

    /// Per-frame effects drawn alongside specific frames (dust puffs while running). The ball is a real toy, not drawn here.
    private func updateFrameProps(for data: SpriteAnimationData, frame: Int) {
        for sub in framePropSublayers { sub.removeFromSuperlayer() }
        framePropSublayers.removeAll()
        guard effectsEnabled else { return }
        let index = ((frame % data.frames.count) + data.frames.count) % data.frames.count
        for placement in data.frameProps where placement.frame == index && placement.prop != "ball" {
            guard let image = library.prop(placement.prop) else { continue }
            let sub = makeSpriteLayer(image: image, frame: propFrame(origin: placement.origin, size: CGSize(width: image.width, height: image.height), in: data))
            emoteLayer.addSublayer(sub)
            framePropSublayers.append(sub)
        }
    }

    /// Converts a prop's canvas position into view coordinates, mirroring with the cat.
    private func propFrame(origin: CGPoint, size: CGSize, in data: SpriteAnimationData) -> CGRect {
        let ppp = pointsPerPixel
        let dx = origin.x - data.anchor.x
        let topAboveGround = data.anchor.y - origin.y
        let x = isFlippedHorizontally ? footPoint.x - (dx + size.width) * ppp : footPoint.x + dx * ppp
        let y = footPoint.y + (topAboveGround - size.height) * ppp
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width * ppp, height: size.height * ppp)
    }

    private func makeSpriteLayer(image: CGImage, frame: CGRect) -> CALayer {
        let sub = CALayer()
        sub.contents = image
        sub.frame = frame
        sub.contentsScale = window?.backingScaleFactor ?? 2
        sub.magnificationFilter = renderQuality == .smooth ? .linear : .nearest
        sub.minificationFilter = renderQuality == .smooth ? .trilinear : .nearest
        return sub
    }

    /// Floats a prop sprite up from a point relative to the cat's head, then fades it.
    /// - Parameters:
    ///   - offset: source pixels from the feet (x along facing direction, y up).
    ///   - drift: total movement in source pixels (x along facing direction, y up).
    func emitParticle(_ prop: String, offset: CGPoint, drift: CGVector, duration: TimeInterval, scale: (from: CGFloat, to: CGFloat) = (0.8, 1.1)) {
        guard effectsEnabled, let image = library.prop(prop) else { return }
        let ppp = pointsPerPixel
        let sign: CGFloat = currentFacing == .right ? 1 : -1
        let size = CGSize(width: CGFloat(image.width) * ppp, height: CGFloat(image.height) * ppp)
        let center = CGPoint(x: footPoint.x + sign * offset.x * ppp, y: footPoint.y + lift + offset.y * ppp)
        let sub = makeSpriteLayer(image: image, frame: CGRect(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded(), width: size.width, height: size.height))
        sub.opacity = 0
        particleLayer.addSublayer(sub)

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: sub.position)
        move.toValue = NSValue(point: CGPoint(x: sub.position.x + sign * drift.dx * ppp, y: sub.position.y + drift.dy * ppp))
        move.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.15, 0.7, 1]
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = scale.from
        grow.toValue = scale.to
        let group = CAAnimationGroup()
        group.animations = [move, fade, grow]
        group.duration = duration
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak sub] in sub?.removeFromSuperlayer() }
        sub.add(group, forKey: "particle")
        CATransaction.commit()
    }

    func clearParticles() {
        particleLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    // MARK: - Shadow

    var forceShadow = false { didSet { updateShadow() } }

    private func updateShadow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let ppp = pointsPerPixel
        let width = 70 * ppp
        let height = 10 * ppp
        shadowLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let bodyShift: CGFloat = isFlippedHorizontally ? 18 : -18
        shadowLayer.position = CGPoint(x: (footPoint.x + bodyShift * ppp).rounded(), y: (footPoint.y - 1 * ppp).rounded())
        let visible = shadowEnabled && (lift > 1 || forceShadow)
        let fade = max(0.35, 1 - lift / (90 * ppp))
        shadowLayer.opacity = visible ? Float(fade) : 0
        CATransaction.commit()
    }

    /// A tiny pixel-art ellipse; scaled up with nearest-neighbour it matches the sprite style.
    private static func makeShadowImage() -> CGImage? {
        let width = 28, height = 4
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rows: [(Int, Int)] = [(6, 21), (2, 25), (2, 25), (6, 21)]
        context.setFillColor(CGColor(red: 0.12, green: 0.1, blue: 0.2, alpha: 0.22))
        for (y, span) in rows.enumerated() {
            context.fill(CGRect(x: span.0, y: y, width: span.1 - span.0 + 1, height: 1))
        }
        return context.makeImage()
    }

    // MARK: - Hit testing

    /// True when `point` (view coordinates) lands on the cat's visible pixels.
    func isCatPixel(at point: CGPoint, tolerance: Int = 2) -> Bool {
        guard let data = currentData else { return false }
        let ppp = pointsPerPixel
        var localX = (point.x - footPoint.x) / ppp
        let localY = (point.y - footPoint.y - lift) / ppp
        if isFlippedHorizontally { localX = -localX }
        let px = Int((data.anchor.x + localX).rounded(.down))
        let py = Int((data.anchor.y - localY).rounded(.down))
        return data.frame(at: currentFrameIndex).mask.isOpaque(x: px, y: py, radius: tolerance)
    }

    /// The cat's visible bounding box in view coordinates.
    var catBounds: CGRect {
        spriteLayer.frame
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseDown(with event: NSEvent) { delegate?.catView(self, mouseDown: event) }
    override func mouseDragged(with event: NSEvent) { delegate?.catView(self, mouseDragged: event) }
    override func mouseUp(with event: NSEvent) { delegate?.catView(self, mouseUp: event) }
    override func rightMouseDown(with event: NSEvent) { delegate?.catView(self, rightMouseDown: event) }
    override func mouseMoved(with event: NSEvent) { delegate?.catView(self, mouseMoved: event) }
    override func mouseExited(with event: NSEvent) { delegate?.catViewMouseExited(self) }
}
