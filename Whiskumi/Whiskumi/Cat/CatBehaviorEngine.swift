import Foundation

/// Things Whiskumi may decide to do on its own.
nonisolated enum CatActivity: String, CaseIterable, Sendable {
    case idle, lookAround, stretch, groom, sit, lieDown, nap, walk
    case yawn, meow, rollOver, box, think, hop, zoomies

    /// Animations an activity cannot do without; activities missing them are never chosen.
    var requiredAnimations: [CatAnimation] {
        switch self {
        case .idle: [.idle]
        case .lookAround: [.lookAround]
        case .stretch: [.stretch]
        case .groom: [.groom]
        case .sit: [.sit]
        case .lieDown: [.lieDown]
        case .nap: [.lieDown, .sleep]
        case .walk: [.walk]
        case .yawn: [.yawn]
        case .meow: [.meow]
        case .rollOver: [.rollOver]
        case .box: [.box]
        case .think: [.think]
        case .hop: [.jump]
        case .zoomies: [.chase]
        }
    }

    var movesCat: Bool { self == .walk || self == .zoomies || self == .hop }
}

/// Everything the engine needs to know to make a decision.
nonisolated struct BehaviorContext: Sendable {
    var needs = CatNeeds()
    var personality = CatPersonality()
    var walkingFrequency = 0.5
    var sleepFrequency = 0.5
    var randomActivities = true
    var autonomousMovement = true
    var available: Set<CatActivity> = Set(CatActivity.allCases)
    var hour = 12
}

/// Weighted random choice of the next autonomous activity.
///
/// The base table follows a natural rhythm (mostly idling, some grooming and
/// stretching, the occasional walk); needs, personality and settings then reshape
/// it, and recently performed activities are damped so the cat doesn't repeat itself.
nonisolated struct CatBehaviorEngine: Sendable {
    /// Base weights in percent-like units. 35 idle, 15 look around, 10 stretch, 10 groom,
    /// 10 sit/lie, 10 walk and 10 shared across everything else.
    static let baseWeights: [CatActivity: Double] = [
        .idle: 35, .lookAround: 15, .stretch: 10, .groom: 10,
        .sit: 4, .lieDown: 6,
        .walk: 10,
        .yawn: 2, .meow: 1.2, .rollOver: 1.6, .box: 1, .think: 0.8, .hop: 1.4, .zoomies: 1.2, .nap: 1.8,
    ]

    private(set) var recent: [CatActivity] = []
    static let memory = 4

    mutating func record(_ activity: CatActivity) {
        recent.append(activity)
        if recent.count > Self.memory { recent.removeFirst(recent.count - Self.memory) }
    }

    func weights(for context: BehaviorContext) -> [(CatActivity, Double)] {
        let needs = context.needs
        let p = context.personality
        var w = Self.baseWeights

        if !context.randomActivities {
            // Only quiet idling — plus a nap when genuinely exhausted.
            return [(.idle, 1), (.nap, needs.energy < 0.2 ? 2 : 0)].filter { context.available.contains($0.0) }
        }

        // Settings
        let walkFactor = 0.15 + 1.85 * context.walkingFrequency
        w[.walk, default: 0] *= walkFactor
        w[.zoomies, default: 0] *= walkFactor
        let sleepFactor = 0.2 + 1.8 * context.sleepFrequency
        w[.nap, default: 0] *= sleepFactor
        w[.lieDown, default: 0] *= 0.5 + sleepFactor * 0.5
        if !context.autonomousMovement {
            for activity in CatActivity.allCases where activity.movesCat { w[activity] = 0 }
        }

        // Personality
        let playful = 0.4 + 1.2 * p.playfulness
        w[.rollOver, default: 0] *= playful
        w[.hop, default: 0] *= playful
        w[.zoomies, default: 0] *= playful
        let lazy = 0.5 + p.laziness
        w[.lieDown, default: 0] *= lazy
        w[.nap, default: 0] *= lazy
        w[.walk, default: 0] *= 1.4 - 0.8 * p.laziness
        let curious = 0.6 + 0.8 * p.curiosity
        w[.lookAround, default: 0] *= curious
        w[.walk, default: 0] *= curious
        w[.box, default: 0] *= 0.6 + p.curiosity

        // Needs
        if needs.energy < 0.3 {
            let tired = (0.3 - needs.energy) / 0.3
            w[.nap, default: 0] *= 1 + tired * 14
            w[.yawn, default: 0] *= 1 + tired * 3
            w[.lieDown, default: 0] *= 1 + tired * 2
            for activity: CatActivity in [.walk, .zoomies, .hop, .rollOver] { w[activity, default: 0] *= 0.25 }
        } else if needs.energy > 0.85 {
            w[.nap, default: 0] *= 0.25
        }
        if needs.fullness < 0.35 || needs.hydration < 0.35 {
            w[.think, default: 0] *= 4
            w[.meow, default: 0] *= 3
        }
        if needs.happiness > 0.75 {
            w[.rollOver, default: 0] *= 1.4
        }

        // Cats are crepuscular: a little sleepier late at night.
        if context.hour >= 23 || context.hour < 6 {
            w[.nap, default: 0] *= 1.5
        }

        // Variety: damp anything done recently (the most recent most strongly).
        for (age, activity) in recent.reversed().enumerated() where activity != .idle {
            w[activity, default: 0] *= age == 0 ? 0.15 : 0.45
        }

        return CatActivity.allCases
            .filter { context.available.contains($0) }
            .map { ($0, max(0, w[$0] ?? 0)) }
    }

    mutating func choose(_ context: BehaviorContext, using generator: inout some RandomNumberGenerator) -> CatActivity {
        let choice = WeightedRandom.pick(weights(for: context), using: &generator) ?? .idle
        record(choice)
        return choice
    }

    mutating func choose(_ context: BehaviorContext) -> CatActivity {
        var generator = SystemRandomNumberGenerator()
        return choose(context, using: &generator)
    }
}
