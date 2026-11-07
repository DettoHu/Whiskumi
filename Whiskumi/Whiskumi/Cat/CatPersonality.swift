import Foundation

/// Long-term tendencies that drift — slowly — with how the user spends time with Whiskumi.
nonisolated struct CatPersonality: Codable, Equatable, Sendable {
    var playfulness: Double = 0.5
    var laziness: Double = 0.5
    var curiosity: Double = 0.5
    var affection: Double = 0.5

    enum Trait: String, CaseIterable, Identifiable, Sendable {
        case playfulness, laziness, curiosity, affection

        var id: String { rawValue }

        var title: String {
            switch self {
            case .playfulness: "Playful"
            case .laziness: "Lazy"
            case .curiosity: "Curious"
            case .affection: "Affectionate"
            }
        }

        var symbolName: String {
            switch self {
            case .playfulness: "figure.play"
            case .laziness: "moon.zzz"
            case .curiosity: "eye"
            case .affection: "heart"
            }
        }
    }

    static let range: ClosedRange<Double> = 0.1...0.9

    /// Every new Whiskumi starts a little different.
    static func newborn() -> CatPersonality {
        func vary() -> Double { (0.5 + Double.random(in: -0.12...0.12)).clamped(to: range) }
        return CatPersonality(playfulness: vary(), laziness: vary(), curiosity: vary(), affection: vary())
    }

    subscript(trait: Trait) -> Double {
        get {
            switch trait {
            case .playfulness: playfulness
            case .laziness: laziness
            case .curiosity: curiosity
            case .affection: affection
            }
        }
        set {
            let value = newValue.clamped(to: Self.range)
            switch trait {
            case .playfulness: playfulness = value
            case .laziness: laziness = value
            case .curiosity: curiosity = value
            case .affection: affection = value
            }
        }
    }

    /// Moves a trait by a small step with diminishing returns near the edges,
    /// and lets opposing traits ease off a touch so the personality stays balanced.
    mutating func nudge(_ trait: Trait, by amount: Double) {
        let current = self[trait]
        let room = amount > 0 ? (Self.range.upperBound - current) : (current - Self.range.lowerBound)
        self[trait] = current + amount * max(0, room) / (Self.range.upperBound - Self.range.lowerBound)
        if amount > 0 {
            switch trait {
            case .playfulness: self[.laziness] -= amount * 0.25
            case .laziness: self[.playfulness] -= amount * 0.25
            default: break
            }
        }
    }

    var dominantTrait: Trait {
        Trait.allCases.max { self[$0] < self[$1] } ?? .curiosity
    }

    var summary: String {
        let sorted = Trait.allCases.sorted { self[$0] > self[$1] }
        let strong = sorted.filter { self[$0] >= 0.58 }
        switch strong.count {
        case 0: return "A calm, well-balanced cat"
        case 1: return "A \(strong[0].title.lowercased()) little cat"
        default: return "A \(strong[0].title.lowercased()), \(strong[1].title.lowercased()) cat"
        }
    }
}
