import CoreGraphics
import QuartzCore

/// How big an art pixel is on screen.
///
/// Nearest-neighbour scaling only stays even when the number of device pixels per art pixel is a
/// simple ratio. Whole numbers are perfectly even, but on a 2× display they only allow a cat of
/// 63 pt (1:1) or 127 pt (2:1). Ratios like 4:3 or 3:2 repeat a fixed pattern (every third or
/// second art pixel is one device pixel wider), which keeps every edge hard — there is never any
/// blending — while allowing sizes in between. "Pixel Perfect" snaps to these ratios and never
/// goes below 1:1, so no art pixel is ever dropped.
nonisolated enum PixelScale {
    /// Points per art pixel at 100 % size: 4 device pixels for every 3 art pixels on a 2× display,
    /// which makes the sitting cat about 85 pt (≈170 Retina pixels) tall.
    static let basePointsPerPixel: CGFloat = 2.0 / 3.0

    /// Device pixels per art pixel that nearest-neighbour sampling renders without irregular gaps.
    static let crispRatios: [CGFloat] = [1, 4.0 / 3.0, 3.0 / 2.0, 5.0 / 3.0, 2, 5.0 / 2.0, 3, 4]

    static func pointsPerPixel(size: Double, quality: RenderQuality, backingScale: CGFloat) -> CGFloat {
        let requested = basePointsPerPixel * CGFloat(size)
        guard quality == .pixelPerfect, backingScale > 0 else { return requested }
        let ratio = requested * backingScale
        let snapped = crispRatios.min { abs($0 - ratio) < abs($1 - ratio) } ?? 1
        return snapped / backingScale
    }
}

/// Lays sprites out on whole device pixels so nothing is ever drawn at a sub-pixel offset.
nonisolated struct PixelGrid: Sendable {
    var backingScale: CGFloat
    var pointsPerPixel: CGFloat

    /// Rounds a length or coordinate in points to the nearest whole device pixel.
    func snap(_ points: CGFloat) -> CGFloat {
        guard backingScale > 0 else { return points.rounded() }
        return (points * backingScale).rounded() / backingScale
    }

    /// A length in art pixels, in points, on whole device pixels.
    func length(_ pixels: CGFloat) -> CGFloat {
        snap(pixels * pointsPerPixel)
    }

    /// The frame of a sprite canvas whose anchor (head centre, ground line) sits on `foot`.
    /// Mirrored sprites mirror around the anchor, so the cat never shifts when it turns.
    func spriteFrame(canvas: CGSize, anchor: CGPoint, flipped: Bool, foot: CGPoint) -> CGRect {
        let width = length(canvas.width)
        let height = length(canvas.height)
        let anchorFromLeft = length(anchor.x)
        let belowGround = height - length(anchor.y)
        let left = flipped ? foot.x - (width - anchorFromLeft) : foot.x - anchorFromLeft
        return CGRect(x: snap(left), y: snap(foot.y - belowGround), width: width, height: height)
    }

    /// The frame of a prop that sat at `origin` (canvas pixels, top-left) on a sprite drawn in `sprite`.
    func propFrame(origin: CGPoint, size: CGSize, onSprite sprite: CGRect, flipped: Bool) -> CGRect {
        let width = length(size.width)
        let height = length(size.height)
        let fromLeft = length(origin.x)
        let x = flipped ? sprite.maxX - fromLeft - width : sprite.minX + fromLeft
        let top = sprite.maxY - length(origin.y)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    /// Whether a value lies exactly on the device-pixel grid.
    func isAligned(_ points: CGFloat) -> Bool {
        abs(points * backingScale - (points * backingScale).rounded()) < 0.001
    }
}

extension CALayer {
    /// Nearest-neighbour sampling, no mipmaps, no edge antialiasing: pixel art stays pixel art.
    /// "Smooth" switches to plain bilinear filtering — still without mipmaps.
    func configureForPixelArt(_ quality: RenderQuality) {
        let filter: CALayerContentsFilter = quality == .smooth ? .linear : .nearest
        magnificationFilter = filter
        minificationFilter = filter
        minificationFilterBias = 0
        allowsEdgeAntialiasing = false
        contentsGravity = .resize
        shouldRasterize = false
    }
}
