import CoreGraphics
import Foundation

nonisolated extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

nonisolated extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
        CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }
}

nonisolated extension CGVector {
    var length: CGFloat { hypot(dx, dy) }

    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
        CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }
}

nonisolated func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

/// Frame-rate independent exponential smoothing factor.
nonisolated func smoothing(rate: Double, dt: Double) -> Double {
    1 - exp(-rate * dt)
}

nonisolated enum WeightedRandom {
    /// Picks one element with probability proportional to its weight. Non-positive weights are ignored.
    static func pick<T>(_ items: [(T, Double)], using generator: inout some RandomNumberGenerator) -> T? {
        let valid = items.filter { $0.1 > 0 }
        let total = valid.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var roll = Double.random(in: 0..<total, using: &generator)
        for (item, weight) in valid {
            if roll < weight { return item }
            roll -= weight
        }
        return valid.last?.0
    }

    static func pick<T>(_ items: [(T, Double)]) -> T? {
        var generator = SystemRandomNumberGenerator()
        return pick(items, using: &generator)
    }
}

nonisolated extension Double {
    /// Random value in range, convenience for behaviour timings.
    static func jitter(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range)
    }
}
