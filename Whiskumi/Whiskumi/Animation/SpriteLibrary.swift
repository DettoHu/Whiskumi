import CoreGraphics
import Foundation
import ImageIO
import os

/// Per-pixel opacity of a frame, used for click-through and hit testing.
nonisolated struct AlphaMask: Sendable {
    let width: Int
    let height: Int
    private let bits: [Bool]

    init(width: Int, height: Int, bits: [Bool]) {
        self.width = width
        self.height = height
        self.bits = bits
    }

    /// `x`/`y` in pixels with a top-left origin.
    func isOpaque(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return bits[y * width + x]
    }

    /// True when any pixel within `radius` is opaque — a forgiving hit test.
    func isOpaque(x: Int, y: Int, radius: Int) -> Bool {
        if isOpaque(x: x, y: y) { return true }
        guard radius > 0 else { return false }
        for dy in -radius...radius {
            for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
                if isOpaque(x: x + dx, y: y + dy) { return true }
            }
        }
        return false
    }

    var topOpaqueRow: Int {
        for y in 0..<height {
            for x in 0..<width where bits[y * width + x] { return y }
        }
        return 0
    }

    static func make(from image: CGImage) -> AlphaMask {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return AlphaMask(width: width, height: height, bits: Array(repeating: true, count: width * height)) }
        var bits = [Bool](repeating: false, count: width * height)
        // CGContext memory is top-row first for this layout.
        for i in 0..<(width * height) where pixels[i * 4 + 3] > 24 {
            bits[i] = true
        }
        return AlphaMask(width: width, height: height, bits: bits)
    }
}

nonisolated final class SpriteFrame: @unchecked Sendable {
    let image: CGImage
    let mask: AlphaMask
    let topOpaqueRow: Int

    init(image: CGImage) {
        self.image = image
        self.mask = AlphaMask.make(from: image)
        self.topOpaqueRow = mask.topOpaqueRow
    }
}

/// Where an effect sprite (heart, "?", ball...) sat in the original art, in canvas pixels (top-left origin).
nonisolated struct PropPlacement: Sendable {
    let prop: String
    let frame: Int
    let origin: CGPoint
}

nonisolated final class SpriteAnimationData: @unchecked Sendable {
    let name: CatAnimation
    let frames: [SpriteFrame]
    /// Canvas size in source pixels.
    let size: CGSize
    /// Head-centre x and ground line y, in canvas pixels with a top-left origin.
    let anchor: CGPoint
    /// Which way the cat faces in the source art.
    let facing: Facing
    let emotes: [PropPlacement]
    let frameProps: [PropPlacement]

    init(name: CatAnimation, frames: [SpriteFrame], size: CGSize, anchor: CGPoint, facing: Facing,
         emotes: [PropPlacement], frameProps: [PropPlacement]) {
        self.name = name
        self.frames = frames
        self.size = size
        self.anchor = anchor
        self.facing = facing
        self.emotes = emotes
        self.frameProps = frameProps
    }

    func frame(at index: Int) -> SpriteFrame {
        frames[((index % frames.count) + frames.count) % frames.count]
    }

    /// Pixels from the anchor to the canvas edges.
    var extentLeft: CGFloat { anchor.x }
    var extentRight: CGFloat { size.width - anchor.x }
    var extentUp: CGFloat { anchor.y }
    var extentDown: CGFloat { size.height - anchor.y }
}

/// How far, in source pixels, anything can reach from the cat's anchor across every animation.
nonisolated struct SpriteExtents: Sendable {
    var horizontal: CGFloat = 0
    var up: CGFloat = 0
    var down: CGFloat = 0
}

nonisolated enum SpriteLibraryError: Error, LocalizedError {
    case manifestMissing
    case manifestUnreadable(String)
    case noUsableAnimations

    var errorDescription: String? {
        switch self {
        case .manifestMissing: "CatAnimations.json was not found in the app bundle."
        case .manifestUnreadable(let reason): "CatAnimations.json could not be read: \(reason)"
        case .noUsableAnimations: "None of Whiskumi's animation frames could be loaded."
        }
    }
}

/// Loads the extracted sprite frames described by `CatAnimations.json`.
nonisolated final class SpriteLibrary: @unchecked Sendable {
    private struct Manifest: Decodable {
        struct Animation: Decodable {
            let frames: [String]
            let size: [Double]
            let anchor: [Double]
            let facing: String?
            let emotes: [Placement]?
            let frameProps: [Placement]?
        }
        struct Placement: Decodable {
            let prop: String
            let frame: Int
            let x: Double
            let y: Double
        }
        struct Prop: Decodable {
            let image: String
            let size: [Double]
        }
        let version: Int
        let animations: [String: Animation]
        let props: [String: Prop]
    }

    private(set) var animations: [CatAnimation: SpriteAnimationData] = [:]
    private(set) var props: [String: CGImage] = [:]
    let extents: SpriteExtents

    init(bundle: Bundle = .main) throws {
        let index = SpriteLibrary.indexResources(in: bundle)
        guard let manifestURL = index["CatAnimations.json"] else { throw SpriteLibraryError.manifestMissing }
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw SpriteLibraryError.manifestUnreadable(error.localizedDescription)
        }

        for (name, entry) in manifest.props {
            if let url = index[entry.image + ".png"], let image = SpriteLibrary.loadImage(url) {
                props[name] = image
            } else {
                Log.sprites.error("Missing prop image \(entry.image, privacy: .public)")
            }
        }

        var loaded: [CatAnimation: SpriteAnimationData] = [:]
        for (key, entry) in manifest.animations {
            guard let name = CatAnimation(rawValue: key) else { continue }
            let frames = entry.frames.compactMap { file -> SpriteFrame? in
                guard let url = index[file + ".png"], let image = SpriteLibrary.loadImage(url) else {
                    Log.sprites.error("Missing frame \(file, privacy: .public)")
                    return nil
                }
                return SpriteFrame(image: image)
            }
            // A partially missing animation would play wrongly; treat it as missing and use fallbacks.
            guard frames.count == entry.frames.count, !frames.isEmpty,
                  entry.size.count == 2, entry.anchor.count == 2 else { continue }
            func placements(_ list: [Manifest.Placement]?) -> [PropPlacement] {
                (list ?? []).map { PropPlacement(prop: $0.prop, frame: $0.frame, origin: CGPoint(x: $0.x, y: $0.y)) }
            }
            loaded[name] = SpriteAnimationData(
                name: name,
                frames: frames,
                size: CGSize(width: entry.size[0], height: entry.size[1]),
                anchor: CGPoint(x: entry.anchor[0].rounded(), y: entry.anchor[1].rounded()),
                facing: entry.facing == "left" ? .left : .right,
                emotes: placements(entry.emotes),
                frameProps: placements(entry.frameProps)
            )
        }
        guard !loaded.isEmpty else { throw SpriteLibraryError.noUsableAnimations }
        animations = loaded
        extents = SpriteLibrary.computeExtents(loaded, props: props)
        Log.sprites.info("Loaded \(loaded.count) animations, \(self.props.count) props")
    }

    /// Exact lookup, no fallbacks.
    func has(_ animation: CatAnimation) -> Bool { animations[animation] != nil }

    /// The requested animation, or the closest available pose.
    func animation(_ animation: CatAnimation) -> SpriteAnimationData? {
        if let exact = animations[animation] { return exact }
        for fallback in animation.fallbacks {
            if let data = animations[fallback] { return data }
        }
        return animations[.idle] ?? animations.values.first
    }

    func prop(_ name: String) -> CGImage? { props[name] }

    // MARK: - Loading helpers

    private static func indexResources(in bundle: Bundle) -> [String: URL] {
        var index: [String: URL] = [:]
        guard let root = bundle.resourceURL,
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return index }
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ext == "png" || ext == "json" else { continue }
            // Prefer the first hit; names are unique by construction.
            if index[url.lastPathComponent] == nil { index[url.lastPathComponent] = url }
        }
        return index
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
    }

    private static func computeExtents(_ animations: [CatAnimation: SpriteAnimationData], props: [String: CGImage]) -> SpriteExtents {
        var extents = SpriteExtents()
        for data in animations.values {
            extents.horizontal = max(extents.horizontal, data.extentLeft, data.extentRight)
            extents.up = max(extents.up, data.extentUp)
            extents.down = max(extents.down, data.extentDown)
            for emote in data.emotes {
                let w = CGFloat(props[emote.prop]?.width ?? 0)
                extents.horizontal = max(extents.horizontal, abs(emote.origin.x - data.anchor.x), abs(emote.origin.x + w - data.anchor.x))
                extents.up = max(extents.up, data.anchor.y - emote.origin.y)
            }
        }
        return extents
    }
}
