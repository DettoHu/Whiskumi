import Foundation

/// Every animation extracted from the supplied sprite sheets. Raw values match
/// the keys in `CatAnimations.json`.
nonisolated enum CatAnimation: String, CaseIterable, Sendable {
    case idle, walk, sit, lieDown, sleep, stretch, playCursor, happy, meow, curious, jump
    case eat, drink, groom, yawn, lookAround, surprised, startled, rollOver, playBall, chase, box
    case heart, sad, think, confused, angry, excited

    /// Poses to fall back to when an animation is missing, ordered by similarity.
    /// The cat is never replaced by something that is not the cat.
    var fallbacks: [CatAnimation] {
        switch self {
        case .idle: [.sit]
        case .sit: [.idle]
        case .walk: [.chase]
        case .chase: [.walk]
        case .lieDown: [.sleep, .sit, .idle]
        case .sleep: [.lieDown, .sit, .idle]
        case .stretch, .yawn, .groom, .lookAround: [.idle]
        case .happy: [.heart, .excited, .idle]
        case .heart: [.happy, .idle]
        case .excited: [.happy, .idle]
        case .meow: [.happy, .idle]
        case .curious: [.confused, .lookAround, .idle]
        case .confused: [.curious, .idle]
        case .think: [.curious, .idle]
        case .surprised: [.startled, .curious, .idle]
        case .startled: [.surprised, .idle]
        case .sad, .angry: [.sit, .idle]
        case .jump: [.chase, .idle]
        case .playCursor: [.playBall, .idle]
        case .playBall: [.playCursor, .idle]
        case .rollOver: [.happy, .idle]
        case .eat: [.drink, .idle]
        case .drink: [.eat, .idle]
        case .box: [.sit, .idle]
        }
    }
}

/// One step of a clip: which frame of the animation, and for how long.
nonisolated struct ClipFrame: Equatable, Sendable {
    let index: Int
    let duration: TimeInterval
}

/// A configurable frame sequence over one animation. Clips can reorder, repeat and
/// hold frames, which is how a handful of drawn frames becomes natural motion.
nonisolated struct AnimationClip: Equatable, Sendable {
    let animation: CatAnimation
    let frames: [ClipFrame]
    var showsEmotes: Bool = true

    static func sequence(_ animation: CatAnimation, _ indices: [Int], fps: Double, emotes: Bool = true) -> AnimationClip {
        AnimationClip(animation: animation, frames: indices.map { ClipFrame(index: $0, duration: 1 / fps) }, showsEmotes: emotes)
    }

    static func timed(_ animation: CatAnimation, _ steps: [(Int, TimeInterval)], emotes: Bool = true) -> AnimationClip {
        AnimationClip(animation: animation, frames: steps.map { ClipFrame(index: $0.0, duration: $0.1) }, showsEmotes: emotes)
    }

    static func pose(_ animation: CatAnimation, frame: Int = 0, for duration: TimeInterval, emotes: Bool = true) -> AnimationClip {
        timed(animation, [(frame, duration)], emotes: emotes)
    }

    var duration: TimeInterval { frames.reduce(0) { $0 + $1.duration } }

    func reversed() -> AnimationClip {
        AnimationClip(animation: animation, frames: frames.reversed(), showsEmotes: showsEmotes)
    }
}

/// The clip catalogue: timings tuned by eye against the supplied frames.
nonisolated enum Clips {
    // Idle (sitting, eyes open) and its little variations.
    static let blink = AnimationClip.timed(.idle, [(3, 0.12), (0, 0.05)])
    static let slowBlink = AnimationClip.timed(.idle, [(2, 0.25), (3, 0.6), (2, 0.25), (0, 0.1)])
    static let contentSmile = AnimationClip.timed(.idle, [(4, 1.4), (0, 0.1)])
    static let idleShift = AnimationClip.timed(.idle, [(1, 0.9), (0, 0.1)])

    static let walk = AnimationClip.sequence(.walk, [0, 1, 2, 3, 4, 5], fps: 10)
    static let run = AnimationClip.sequence(.chase, [0, 1, 2, 3], fps: 13)

    static let lieDown = AnimationClip.timed(.lieDown, [(0, 0.35), (1, 0.4), (2, 0.5)])
    static let getUp = AnimationClip.timed(.lieDown, [(2, 0.25), (1, 0.3), (0, 0.3)])
    static let breathe = AnimationClip.timed(.sleep, [(0, 1.3), (1, 1.1), (2, 1.4), (1, 1.1)], emotes: false)

    static let stretch = AnimationClip.timed(.stretch, [(1, 0.8), (2, 1.2), (1, 0.45)])
    static let wakeStretch = AnimationClip.timed(.stretch, [(0, 0.7), (1, 0.8), (2, 1.1)])
    static let yawn = AnimationClip.timed(.yawn, [(0, 0.3), (1, 0.35), (2, 1.0), (1, 0.25), (3, 0.6)])
    static let groom = AnimationClip.sequence(.groom, [0, 1, 2, 3, 4, 5], fps: 5)
    static let lookAround = AnimationClip.timed(.lookAround, [(1, 0.7), (0, 0.6), (3, 0.9), (4, 1.0), (2, 0.6), (1, 0.6)])
    static let glance = AnimationClip.timed(.lookAround, [(3, 0.8), (4, 0.7), (1, 0.4)])

    static let jump = AnimationClip.timed(.jump, [(0, 0.22), (1, 0.16), (2, 0.2), (3, 0.24)])
    static let rollOver = AnimationClip.timed(.rollOver, [(0, 0.35), (1, 0.45), (2, 0.6), (1, 0.4), (2, 0.6), (3, 0.6)])
    static let playCursor = AnimationClip.timed(.playCursor, [(0, 0.45), (1, 0.22), (0, 0.22), (1, 0.22), (2, 0.35), (3, 0.6), (2, 0.3)])
    static let batBall = AnimationClip.timed(.playBall, [(0, 0.3), (1, 0.22), (2, 0.3), (3, 0.4)])

    static let eatStart = AnimationClip.timed(.eat, [(0, 0.5)])
    static let eatLoop = AnimationClip.timed(.eat, [(1, 0.3), (2, 0.28), (3, 0.3), (2, 0.28)])
    static let eatFinish = AnimationClip.timed(.eat, [(4, 1.1)])
    static let drinkStart = AnimationClip.timed(.drink, [(0, 0.5)])
    static let drinkLoop = AnimationClip.timed(.drink, [(1, 0.26), (2, 0.24), (3, 0.26), (2, 0.24)])
    static let drinkFinish = AnimationClip.timed(.drink, [(4, 0.9)])

    static let boxSettle = AnimationClip.timed(.box, [(0, 1.1), (1, 0.9), (0, 0.5), (2, 1.4)])
    static let boxDoze = AnimationClip.timed(.box, [(3, 2.4), (2, 0.6)])

    static let surprised = AnimationClip.timed(.surprised, [(0, 0.3), (1, 1.0)])
    static let startled = AnimationClip.timed(.startled, [(0, 0.25), (1, 0.55), (2, 0.6)])

    static let happy = AnimationClip.pose(.happy, for: 1.6)
    static let heart = AnimationClip.pose(.heart, for: 1.8)
    static let meow = AnimationClip.pose(.meow, for: 1.1)
    static let curious = AnimationClip.pose(.curious, for: 1.6)
    static let confused = AnimationClip.pose(.confused, for: 1.5)
    static let think = AnimationClip.pose(.think, for: 2.4)
    static let sad = AnimationClip.pose(.sad, for: 1.8)
    static let angry = AnimationClip.pose(.angry, for: 1.4)
    static let excited = AnimationClip.pose(.excited, for: 1.3)

    /// Every clip above, for validation against the loaded sprites.
    static let all: [AnimationClip] = [
        blink, slowBlink, contentSmile, idleShift, walk, run, lieDown, getUp, breathe, stretch, wakeStretch,
        yawn, groom, lookAround, glance, jump, rollOver, playCursor, batBall, eatStart, eatLoop, eatFinish,
        drinkStart, drinkLoop, drinkFinish, boxSettle, boxDoze, surprised, startled, happy, heart, meow,
        curious, confused, think, sad, angry, excited,
    ]
}
