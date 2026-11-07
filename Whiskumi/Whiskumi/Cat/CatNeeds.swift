import Foundation

/// Whiskumi's gentle virtual-pet needs. Every value is 0...1 where higher is better,
/// except that the UI also exposes `hunger` / `thirst` (their inverses).
///
/// The model is deliberately forgiving: values drift slowly, never hit zero from
/// neglect alone, and time spent with the app closed only counts partially.
nonisolated struct CatNeeds: Codable, Equatable, Sendable {
    var fullness: Double = 0.8
    var hydration: Double = 0.8
    var energy: Double = 0.9
    var happiness: Double = 0.7
    var affection: Double = 0.35

    var hunger: Double { 1 - fullness }
    var thirst: Double { 1 - hydration }

    enum Rates {
        static let fullnessPerHour = 0.09
        static let hydrationPerHour = 0.12
        static let energyAwakePerHour = 0.32
        static let energyActivePerHour = 0.9
        static let energySleepingPerHour = 1.8
        static let affectionPerHour = 0.05
        static let happinessDriftPerHour = 0.15
    }

    /// Floors that passive decay never goes below — Whiskumi is never in real trouble.
    enum Floors {
        static let fullness = 0.05
        static let hydration = 0.05
        static let energy = 0.08
        static let affection = 0.15
        static let offlineFullness = 0.3
        static let offlineHydration = 0.3
    }

    /// Advances needs for time spent with the app running.
    /// - Parameter activity: 0 when resting, 1 while walking/playing.
    mutating func advance(by seconds: TimeInterval, sleeping: Bool, activity: Double = 0) {
        guard seconds > 0 else { return }
        let hours = seconds / 3600
        fullness = max(Floors.fullness, fullness - Rates.fullnessPerHour * hours)
        hydration = max(Floors.hydration, hydration - Rates.hydrationPerHour * hours)
        if sleeping {
            energy = min(1, energy + Rates.energySleepingPerHour * hours)
        } else {
            let drain = lerp(Rates.energyAwakePerHour, Rates.energyActivePerHour, activity.clamped(to: 0...1))
            energy = max(Floors.energy, energy - drain * hours)
        }
        affection = max(Floors.affection, affection - Rates.affectionPerHour * hours)
        let step = Rates.happinessDriftPerHour * hours
        happiness += (happinessTarget - happiness).clamped(to: -step...step)
        clamp()
    }

    /// Applies time that passed while the app was closed. Only part of it counts, it is capped,
    /// and Whiskumi is assumed to have napped meanwhile.
    mutating func applyOfflineTime(_ seconds: TimeInterval) {
        guard seconds > 60 else { return }
        let counted = min(seconds, 12 * 3600) * 0.5
        let hours = counted / 3600
        fullness = max(min(fullness, Floors.offlineFullness), fullness - Rates.fullnessPerHour * hours)
        hydration = max(min(hydration, Floors.offlineHydration), hydration - Rates.hydrationPerHour * hours)
        energy = min(1, energy + Rates.energySleepingPerHour * hours * 0.5)
        affection = max(Floors.affection, affection - Rates.affectionPerHour * hours)
        happiness += (0.55 - happiness) * min(1, hours / 6)
        clamp()
    }

    /// Happiness slowly settles where the cat's comfort says it should be.
    var happinessTarget: Double {
        let comfort = (fullness + hydration + min(1, energy + 0.2)) / 3
        return (0.25 + 0.45 * comfort + 0.3 * affection).clamped(to: 0...1)
    }

    var overall: Double { (fullness + hydration + energy + happiness) / 4 }

    mutating func eat(nourishment: Double, joy: Double) {
        fullness += nourishment
        happiness += joy
        clamp()
    }

    mutating func drink(_ amount: Double) {
        hydration += amount
        happiness += 0.03
        clamp()
    }

    mutating func receivePets(intensity: Double = 1) {
        affection += 0.035 * intensity
        happiness += 0.025 * intensity
        clamp()
    }

    mutating func play(intensity: Double = 1) {
        happiness += 0.05 * intensity
        affection += 0.015 * intensity
        energy -= 0.03 * intensity
        energy = max(Floors.energy, energy)
        clamp()
    }

    mutating func clamp() {
        fullness = fullness.clamped(to: 0...1)
        hydration = hydration.clamped(to: 0...1)
        energy = energy.clamped(to: 0...1)
        happiness = happiness.clamped(to: 0...1)
        affection = affection.clamped(to: 0...1)
    }
}
