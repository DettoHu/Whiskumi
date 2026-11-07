import CoreGraphics
import Foundation

/// Something that can put a sprite frame on screen.
protocol CatRenderer: AnyObject {
    func display(_ animation: SpriteAnimationData, frame: Int, facing: Facing, showEmotes: Bool)
}

/// Plays clips frame by frame. Playback is `async` and cancellation-aware, so any
/// animation can be interrupted at any frame simply by cancelling the task running it.
/// Frames are scheduled with `Task.sleep`, so a held pose costs nothing between frames.
final class SpriteAnimationController {
    let library: SpriteLibrary
    weak var renderer: CatRenderer?

    /// Global playback speed multiplier from settings.
    var speed: Double = 1.0

    var facing: Facing = .right {
        didSet { if oldValue != facing { redisplay() } }
    }

    private(set) var currentAnimation: CatAnimation = .idle
    private(set) var currentFrame: Int = 0
    private(set) var currentData: SpriteAnimationData?
    private var emotesVisible = false

    /// Observers (e.g. the menu bar preview) learn about every displayed frame.
    var onFrameChange: ((SpriteAnimationData, Int, Facing) -> Void)?

    init(library: SpriteLibrary) {
        self.library = library
    }

    func show(_ animation: CatAnimation, frame: Int = 0, emotes: Bool = true) {
        guard let data = library.animation(animation) else { return }
        let changedAnimation = currentData !== data
        currentAnimation = animation
        currentData = data
        currentFrame = frame
        // Emotes belong to a pose; only (re)show them when the pose changes or a clip asks.
        let showEmotes = emotes && (changedAnimation || !emotesVisible)
        emotesVisible = emotes
        renderer?.display(data, frame: frame, facing: facing, showEmotes: showEmotes)
        onFrameChange?(data, frame, facing)
    }

    func redisplay() {
        guard let data = currentData else { return }
        renderer?.display(data, frame: currentFrame, facing: facing, showEmotes: emotesVisible)
        onFrameChange?(data, currentFrame, facing)
    }

    /// Plays a clip once.
    func play(_ clip: AnimationClip) async throws {
        for step in clip.frames {
            try Task.checkCancellation()
            show(clip.animation, frame: step.index, emotes: clip.showsEmotes)
            try await Task.sleep(for: .seconds(step.duration / max(0.1, speed)))
        }
    }

    /// Repeats a clip until cancelled.
    func loop(_ clip: AnimationClip) async throws {
        while true {
            try await play(clip)
        }
    }

    /// Repeats a clip for roughly `duration` seconds (always finishing the current cycle).
    func loop(_ clip: AnimationClip, for duration: TimeInterval) async throws {
        let end = Date().addingTimeInterval(duration / max(0.1, speed))
        repeat {
            try await play(clip)
        } while Date() < end
    }

    /// Shows a single frame and waits.
    func hold(_ animation: CatAnimation, frame: Int = 0, for duration: TimeInterval, emotes: Bool = true) async throws {
        show(animation, frame: frame, emotes: emotes)
        try await Task.sleep(for: .seconds(duration / max(0.1, speed)))
    }

    /// Head position (top of the ears, roughly centred) relative to the anchor, in source pixels, y up.
    func headOffset() -> CGPoint {
        guard let data = currentData else { return CGPoint(x: 0, y: 100) }
        let top = CGFloat(data.frame(at: currentFrame).topOpaqueRow)
        return CGPoint(x: 0, y: data.anchor.y - top)
    }
}
