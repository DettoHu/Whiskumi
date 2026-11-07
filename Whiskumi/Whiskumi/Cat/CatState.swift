import Foundation

/// What Whiskumi is doing right now. Drives the mood text and which interactions make sense.
nonisolated enum CatState: String, Sendable {
    case idle, walking, sitting, lyingDown, sleeping, stretching, playing, grooming
    case eating, drinking, yawning, curious, happy, surprised, meowing
    case carried, chasing, thinking, hiding, rolling

    var displayName: String {
        switch self {
        case .idle: "Relaxing"
        case .walking: "Strolling"
        case .sitting: "Sitting"
        case .lyingDown: "Lounging"
        case .sleeping: "Sleeping"
        case .stretching: "Stretching"
        case .playing: "Playing"
        case .grooming: "Grooming"
        case .eating: "Eating"
        case .drinking: "Drinking"
        case .yawning: "Yawning"
        case .curious: "Curious"
        case .happy: "Happy"
        case .surprised: "Surprised"
        case .meowing: "Meowing"
        case .carried: "Being carried"
        case .chasing: "Chasing"
        case .thinking: "Thinking"
        case .hiding: "In a box"
        case .rolling: "Rolling around"
        }
    }

    var isAsleep: Bool { self == .sleeping }
}

nonisolated enum Facing: String, Codable, Sendable {
    case left, right

    var opposite: Facing { self == .left ? .right : .left }
    var sign: CGFloat { self == .right ? 1 : -1 }

    static func toward(dx: CGFloat) -> Facing { dx >= 0 ? .right : .left }
}

/// Body position, used to pick natural transitions (e.g. get up before walking).
nonisolated enum Posture: Sendable {
    case sitting, lying, sleeping, inBox
}

nonisolated enum CatMood: String, Sendable {
    case content, happy, loving, playful, sleepy, sleeping, peckish, hungry, thirsty, curious

    var title: String {
        switch self {
        case .content: "Content"
        case .happy: "Happy"
        case .loving: "Feeling loved"
        case .playful: "Playful"
        case .sleepy: "Sleepy"
        case .sleeping: "Fast asleep"
        case .peckish: "A little peckish"
        case .hungry: "Hungry"
        case .thirsty: "Thirsty"
        case .curious: "Curious"
        }
    }

    var symbolName: String {
        switch self {
        case .content: "face.smiling"
        case .happy: "sun.max"
        case .loving: "heart.fill"
        case .playful: "sparkles"
        case .sleepy: "moon"
        case .sleeping: "moon.zzz.fill"
        case .peckish: "fork.knife"
        case .hungry: "fork.knife"
        case .thirsty: "drop"
        case .curious: "eye"
        }
    }

    static func evaluate(needs: CatNeeds, state: CatState) -> CatMood {
        if state == .sleeping { return .sleeping }
        if needs.fullness < 0.2 { return .hungry }
        if needs.hydration < 0.2 { return .thirsty }
        if needs.energy < 0.22 { return .sleepy }
        if state == .playing || state == .chasing { return .playful }
        if state == .curious { return .curious }
        if needs.affection > 0.72 && needs.happiness > 0.65 { return .loving }
        if needs.fullness < 0.38 { return .peckish }
        if needs.happiness > 0.72 { return .happy }
        return .content
    }
}
