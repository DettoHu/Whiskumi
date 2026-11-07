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
/// lifted from the art (hearts, Zs, "?"), and a small pixel shadow.
///
/// Everything is laid out on whole device pixels through `PixelGrid` and sampled with
/// nearest-neighbour filtering, and effects move in whole-pixel steps instead of gliding
/// or scaling, so the art never gets resampled between pixels.
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

    /// Visual lift of the sprite above its feet position (carrying, hopping). Applied in whole device pixels.
    var lift: CGFloat = 0 { didSet { if grid.snap(lift) != grid.snap(oldValue) { redisplay() } } }

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
    /// The sprite's device-pixel-aligned frame, including lift.
    private(set) var spriteFrame: CGRect = .zero
    /// The same frame without lift; effects are placed against it and lifted as a group.
    private var restingSpriteFrame: CGRect = .zero

    private static let shadowSize = CGSize(width: 64, height: 9)

    init(library: SpriteLibrary) {
        self.library = library
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let root = layer else { return }
        root.backgroundColor = .clear
        root.masksToBounds = false
        for sub in [shadowLayer, spriteLayer, emoteLayer, particleLayer] {
            sub.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "transform": NSNull(),
                           "anchorPoint": NSNull(), "opacity": NSNull(), "frame": NSNull()]
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
        for sub in [spriteLayer, shadowLayer, emoteLayer, particleLayer] { sub.contentsScale = backingScale }
        redisplay()
    }

    var backingScale: CGFloat {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return scale > 0 ? scale : 2
    }

    var grid: PixelGrid { PixelGrid(backingScale: backingScale, pointsPerPixel: pointsPerPixel) }

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
        let grid = grid
        let foot = CGPoint(x: grid.snap(footPoint.x), y: grid.snap(footPoint.y))
        let lifted = grid.snap(lift)
        restingSpriteFrame = grid.spriteFrame(canvas: data.size, anchor: data.anchor, flipped: isFlippedHorizontally, foot: foot)
        spriteFrame = restingSpriteFrame.offsetBy(dx: 0, dy: lifted)
        spriteLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        spriteLayer.bounds = CGRect(origin: .zero, size: spriteFrame.size)
        spriteLayer.position = CGPoint(x: spriteFrame.midX, y: spriteFrame.midY)
        // Mirroring about the centre keeps the (already aligned) frame exactly where it is.
        spriteLayer.setAffineTransform(isFlippedHorizontally ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        emoteLayer.frame = bounds
        emoteLayer.setAffineTransform(CGAffineTransform(translationX: 0, y: lifted))
        particleLayer.frame = bounds
        updateShadow()
    }

    private func applyFilters() {
        for sub in [spriteLayer, shadowLayer, emoteLayer, particleLayer] { sub.configureForPixelArt(renderQuality) }
        for sub in emoteSublayers + framePropSublayers + (particleLayer.sublayers ?? []) {
            sub.configureForPixelArt(renderQuality)
        }
    }

    // MARK: - Emotes and particles

    private func clearEmotes() {
        for sub in emoteSublayers { sub.removeFromSuperlayer() }
        emoteSublayers.removeAll()
    }

    /// Effects drawn in the source art, placed exactly where the artist put them. They pop in
    /// with a two-step hop and bob in whole pixels — stepped like the sprite, never scaled.
    private func presentEmotes(for data: SpriteAnimationData) {
        let grid = grid
        let step = max(grid.length(3), 1 / backingScale)
        for (i, placement) in data.emotes.enumerated() {
            guard let image = library.prop(placement.prop) else { continue }
            let frame = grid.propFrame(origin: placement.origin, size: CGSize(width: image.width, height: image.height),
                                       onSprite: restingSpriteFrame, flipped: isFlippedHorizontally)
            let sub = makeSpriteLayer(image: image, frame: frame)
            emoteLayer.addSublayer(sub)
            emoteSublayers.append(sub)
            let y = sub.position.y
            let start = CACurrentMediaTime() + Double(i) * 0.08

            let appear = CAKeyframeAnimation(keyPath: "opacity")
            appear.values = [0, 1]
            appear.keyTimes = [0, 0.5]
            appear.calculationMode = .discrete
            appear.duration = 0.1
            appear.beginTime = start
            appear.fillMode = .backwards
            sub.add(appear, forKey: "appear")

            let pop = CAKeyframeAnimation(keyPath: "position.y")
            pop.values = [y - step, y + step, y]
            pop.keyTimes = [0, 0.4, 0.75]
            pop.calculationMode = .discrete
            pop.duration = 0.3
            pop.beginTime = start
            pop.fillMode = .backwards
            sub.add(pop, forKey: "pop")

            let bob = CAKeyframeAnimation(keyPath: "position.y")
            bob.values = [y, y + step]
            bob.keyTimes = [0, 0.5]
            bob.calculationMode = .discrete
            bob.duration = 1.0
            bob.repeatCount = .infinity
            bob.beginTime = start + 0.35 + Double(i) * 0.15
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
            let frame = grid.propFrame(origin: placement.origin, size: CGSize(width: image.width, height: image.height),
                                       onSprite: restingSpriteFrame, flipped: isFlippedHorizontally)
            let sub = makeSpriteLayer(image: image, frame: frame)
            emoteLayer.addSublayer(sub)
            framePropSublayers.append(sub)
        }
    }

    private func makeSpriteLayer(image: CGImage, frame: CGRect) -> CALayer {
        let sub = CALayer()
        sub.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull()]
        sub.contents = image
        sub.frame = frame
        sub.contentsScale = backingScale
        sub.configureForPixelArt(renderQuality)
        return sub
    }

    /// Floats a prop sprite up from a point relative to the cat's head, then fades it. The motion is
    /// a short sequence of whole-device-pixel positions (about 10 per second), like sprite animation.
    /// - Parameters:
    ///   - offset: source pixels from the feet (x along facing direction, y up) to the prop's centre.
    ///   - drift: total movement in source pixels (x along facing direction, y up).
    func emitParticle(_ prop: String, offset: CGPoint, drift: CGVector, duration: TimeInterval) {
        guard effectsEnabled, let image = library.prop(prop) else { return }
        let grid = grid
        let sign: CGFloat = currentFacing == .right ? 1 : -1
        let size = CGSize(width: grid.length(CGFloat(image.width)), height: grid.length(CGFloat(image.height)))
        let foot = CGPoint(x: grid.snap(footPoint.x), y: grid.snap(footPoint.y) + grid.snap(lift))
        let origin = CGPoint(x: grid.snap(foot.x + sign * offset.x * pointsPerPixel - size.width / 2),
                             y: grid.snap(foot.y + offset.y * pointsPerPixel - size.height / 2))
        let sub = makeSpriteLayer(image: image, frame: CGRect(origin: origin, size: size))
        sub.opacity = 0
        particleLayer.addSublayer(sub)

        let steps = max(6, Int(duration * 10))
        var positions: [NSValue] = []
        var times: [NSNumber] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let eased = CGFloat(1 - pow(1 - t, 2))
            // Snap the frame origin (not the centre) so odd-sized sprites stay on the grid too.
            let x = grid.snap(origin.x + sign * drift.dx * pointsPerPixel * eased) + size.width / 2
            let y = grid.snap(origin.y + drift.dy * pointsPerPixel * eased) + size.height / 2
            positions.append(NSValue(point: CGPoint(x: x, y: y)))
            times.append(NSNumber(value: t))
        }
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = positions
        move.keyTimes = times
        move.calculationMode = .discrete
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0.6, 0]
        fade.keyTimes = [0, 0.08, 0.65, 0.85, 1]
        fade.calculationMode = .discrete
        let group = CAAnimationGroup()
        group.animations = [move, fade]
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
        let grid = grid
        let size = CGSize(width: grid.length(Self.shadowSize.width), height: grid.length(Self.shadowSize.height))
        // Centre the shadow under the body rather than the head (the anchor).
        let bodyShift = (isFlippedHorizontally ? 18 : -18) * pointsPerPixel
        let x = grid.snap(grid.snap(footPoint.x) + bodyShift - size.width / 2)
        let y = grid.snap(footPoint.y) - grid.length(5)
        shadowLayer.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        let lifted = grid.snap(lift)
        let visible = shadowEnabled && (lifted > 0 || forceShadow)
        shadowLayer.opacity = visible ? (lifted > grid.length(60) ? 0.6 : 1) : 0
        CATransaction.commit()
    }

    /// A blocky ellipse in art pixels (3-pixel steps), drawn at the same scale as the sprite.
    private static func makeShadowImage() -> CGImage? {
        let width = Int(shadowSize.width), height = Int(shadowSize.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.12, green: 0.1, blue: 0.2, alpha: 0.22))
        context.fill(CGRect(x: 9, y: 0, width: 46, height: 3))
        context.fill(CGRect(x: 0, y: 3, width: 64, height: 3))
        context.fill(CGRect(x: 9, y: 6, width: 46, height: 3))
        return context.makeImage()
    }

    // MARK: - Hit testing

    /// True when `point` (view coordinates) lands on the cat's visible pixels.
    /// Uses the exact inverse of the layout, so it matches what is drawn.
    func isCatPixel(at point: CGPoint, tolerance: Int = 2) -> Bool {
        guard let data = currentData, spriteFrame.width > 0, spriteFrame.height > 0 else { return false }
        var u = (point.x - spriteFrame.minX) / spriteFrame.width
        let v = (spriteFrame.maxY - point.y) / spriteFrame.height
        if isFlippedHorizontally { u = 1 - u }
        let px = Int((u * data.size.width).rounded(.down))
        let py = Int((v * data.size.height).rounded(.down))
        return data.frame(at: currentFrameIndex).mask.isOpaque(x: px, y: py, radius: tolerance)
    }

    /// The cat's visible bounding box in view coordinates.
    var catBounds: CGRect {
        spriteFrame
    }

    /// Debug/verification: every on-screen layer that draws pixel art.
    var pixelArtLayers: [CALayer] {
        [spriteLayer, shadowLayer] + emoteSublayers + framePropSublayers + (particleLayer.sublayers ?? [])
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
