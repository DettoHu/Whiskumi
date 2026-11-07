import CoreGraphics
import Foundation

/// Recognises petting gestures: clicks, gentle back-and-forth rubbing with the pointer,
/// and enthusiastic over-petting.
nonisolated struct PettingHandler: Sendable {
    enum ClickResult: Equatable, Sendable { case pet, overPetted }

    private var clickTimes: [TimeInterval] = []
    private var lastOverPet: TimeInterval = -.infinity
    private var rubSamples: [(x: CGFloat, t: TimeInterval)] = []
    private var lastRub: TimeInterval = -.infinity

    static let overPetClicks = 7
    static let overPetWindow: TimeInterval = 3
    static let overPetCooldown: TimeInterval = 12

    mutating func registerClick(at time: TimeInterval) -> ClickResult {
        clickTimes.append(time)
        clickTimes.removeAll { time - $0 > Self.overPetWindow }
        if clickTimes.count >= Self.overPetClicks, time - lastOverPet > Self.overPetCooldown {
            lastOverPet = time
            clickTimes.removeAll()
            return .overPetted
        }
        return .pet
    }

    /// Feed pointer positions while it hovers over the cat. Returns true when the motion
    /// looks like stroking: several direction changes covering some distance, recently.
    mutating func registerHover(x: CGFloat, at time: TimeInterval) -> Bool {
        rubSamples.append((x, time))
        rubSamples.removeAll { time - $0.t > 1.5 }
        guard rubSamples.count >= 4, time - lastRub > 1.6 else { return false }
        var reversals = 0
        var travel: CGFloat = 0
        var direction: CGFloat = 0
        var segment: CGFloat = 0
        for i in 1..<rubSamples.count {
            let dx = rubSamples[i].x - rubSamples[i - 1].x
            travel += abs(dx)
            guard abs(dx) > 0.5 else { continue }
            let sign: CGFloat = dx > 0 ? 1 : -1
            if direction != 0, sign != direction {
                if segment >= 6 { reversals += 1 }
                segment = 0
            }
            direction = sign
            segment += abs(dx)
        }
        if reversals >= 3, travel > 60 {
            lastRub = time
            rubSamples.removeAll()
            return true
        }
        return false
    }

    mutating func resetHover() {
        rubSamples.removeAll()
    }
}
