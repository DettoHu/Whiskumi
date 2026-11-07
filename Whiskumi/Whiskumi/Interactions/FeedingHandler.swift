import Foundation

nonisolated enum FoodItem: String, CaseIterable, Identifiable, Sendable {
    case kibble, tuna, salmonTreat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kibble: "Kibble"
        case .tuna: "Tuna"
        case .salmonTreat: "Salmon Treat"
        }
    }

    var detail: String {
        switch self {
        case .kibble: "A proper meal"
        case .tuna: "A favourite feast"
        case .salmonTreat: "A little indulgence"
        }
    }

    var symbolName: String {
        switch self {
        case .kibble: "circle.hexagongrid.fill"
        case .tuna: "fish.fill"
        case .salmonTreat: "star.fill"
        }
    }

    var nourishment: Double {
        switch self {
        case .kibble: 0.35
        case .tuna: 0.5
        case .salmonTreat: 0.15
        }
    }

    var joy: Double {
        switch self {
        case .kibble: 0.04
        case .tuna: 0.1
        case .salmonTreat: 0.12
        }
    }

    /// Seconds of munching.
    var eatingTime: TimeInterval {
        switch self {
        case .kibble: 5
        case .tuna: 6.5
        case .salmonTreat: 2.5
        }
    }
}

/// Feeding and watering routines.
struct FeedingHandler {
    unowned let cat: CatController

    /// Treats are always welcome; full meals only when there's room.
    func canEat(_ food: FoodItem) -> Bool {
        guard cat.library.has(.eat) else { return false }
        return food == .salmonTreat ? cat.needs.fullness < 0.97 : cat.needs.fullness < 0.92
    }

    var canFeed: Bool { FoodItem.allCases.contains(where: canEat) }

    var canDrink: Bool { cat.library.has(.drink) && cat.needs.hydration < 0.95 }

    func eat(_ food: FoodItem) async throws {
        try await cat.getUpIfNeeded()
        cat.setState(.eating)
        // Apply the meal up front so an interruption never loses it.
        cat.mutateNeeds { $0.eat(nourishment: food.nourishment, joy: food.joy) }
        cat.recordStat { $0.meals += 1 }
        cat.personalityNudge(.affection, 0.004)
        if cat.library.has(.excited) {
            try await cat.animator.play(.pose(.excited, for: 0.7))
        }
        try await cat.animator.play(Clips.eatStart)
        cat.audio.play(.eat)
        try await cat.animator.loop(Clips.eatLoop, for: food.eatingTime)
        try await cat.animator.play(Clips.eatFinish)
        if food == .tuna || food == .salmonTreat {
            cat.emitHearts(count: 2)
        }
        if cat.library.has(.groom) {
            cat.setState(.grooming)
            try await cat.animator.loop(Clips.groom, for: 1.5)
        }
    }

    func drink() async throws {
        try await cat.getUpIfNeeded()
        cat.setState(.drinking)
        cat.mutateNeeds { $0.drink(0.45) }
        cat.recordStat { $0.drinks += 1 }
        try await cat.animator.play(Clips.drinkStart)
        cat.audio.play(.drink)
        try await cat.animator.loop(Clips.drinkLoop, for: 4)
        try await cat.animator.play(Clips.drinkFinish)
    }
}
