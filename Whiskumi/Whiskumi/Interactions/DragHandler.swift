import AppKit

/// Picking Whiskumi up: the cat follows the pointer on a soft spring, dangles in a
/// surprised pose (or "flies" when swung quickly), then lands and composes itself.
final class DragHandler {
    unowned let cat: CatController
    private(set) var isCarrying = false
    private var cursor: CGPoint = .zero
    private var grabOffset: CGVector = .zero
    private var released = false
    private var cursorVelocity: CGVector = .zero
    private var lastSample: (point: CGPoint, time: TimeInterval)?

    init(cat: CatController) {
        self.cat = cat
    }

    func begin(at point: CGPoint) {
        guard cat.isVisible else { return }
        cursor = point
        grabOffset = cat.windows.foot - point
        released = false
        cursorVelocity = .zero
        lastSample = nil
        isCarrying = true
        cat.windows.forceInteractive = true
        let started = cat.perform(.carried) { [weak self] cat in
            try await self?.carry(cat)
        }
        if !started {
            isCarrying = false
            cat.windows.forceInteractive = false
        }
    }

    func move(to point: CGPoint, time: TimeInterval) {
        if let last = lastSample, time > last.time {
            let dt = time - last.time
            let instant = CGVector(dx: (point.x - last.point.x) / dt, dy: (point.y - last.point.y) / dt)
            let k = CGFloat(smoothing(rate: 16, dt: dt))
            cursorVelocity = CGVector(dx: cursorVelocity.dx + (instant.dx - cursorVelocity.dx) * k,
                                      dy: cursorVelocity.dy + (instant.dy - cursorVelocity.dy) * k)
        }
        lastSample = (point, time)
        cursor = point
    }

    func end() {
        released = true
    }

    private func carry(_ cat: CatController) async throws {
        let windows = cat.windows
        let view = windows.catView
        defer {
            isCarrying = false
            windows.forceInteractive = false
            view.lift = 0
            view.forceShadow = false
        }
        // A sleeping cat scooped up is wide awake at once — and a little confused about it.
        let wasAsleep = cat.posture == .sleeping
        cat.posture = .sitting
        cat.setState(.carried)
        view.clearParticles()
        view.forceShadow = true
        cat.animator.show(.surprised, frame: 0)

        let ppp = windows.pointsPerPixel
        let liftHeight = 12 * ppp
        var feet = windows.foot
        var lift: CGFloat = 0
        var velocity = CGVector.zero
        var elapsed: TimeInterval = 0
        try await windows.clock.run { [weak self] dt in
            guard let self else { return false }
            elapsed += dt
            let k = CGFloat(smoothing(rate: 20, dt: dt))
            lift += (liftHeight - lift) * k
            // Feet hang below the grab point; the sprite is lifted so the grabbed spot stays under the pointer.
            let target = CGPoint(x: self.cursor.x + self.grabOffset.dx, y: self.cursor.y + self.grabOffset.dy - lift)
            let next = CGPoint(x: feet.x + (target.x - feet.x) * k, y: feet.y + (target.y - feet.y) * k)
            if dt > 0 {
                let instant = CGVector(dx: (next.x - feet.x) / dt, dy: (next.y - feet.y) / dt)
                velocity = CGVector(dx: velocity.dx + (instant.dx - velocity.dx) * 0.3, dy: velocity.dy + (instant.dy - velocity.dy) * 0.3)
            }
            feet = next
            windows.moveFoot(to: feet)
            view.lift = lift
            if elapsed > 0.18 {
                if velocity.length > 700, cat.library.has(.jump) {
                    if abs(velocity.dx) > 80 { cat.facing = .toward(dx: velocity.dx) }
                    cat.animator.show(.jump, frame: 1, emotes: false)
                } else {
                    cat.animator.show(.surprised, frame: 1)
                }
            }
            return !self.released
        }

        // A little momentum after letting go, then settle within the screen.
        var toss = cursorVelocity
        if toss.length > 900 { toss = toss * (900 / toss.length) }
        var t: TimeInterval = 0
        try await windows.clock.run { dt in
            t += dt
            toss = toss * CGFloat(exp(-10 * dt))
            feet = feet + toss * CGFloat(dt)
            lift = max(0, lift - liftHeight * CGFloat(dt / 0.16))
            windows.moveFoot(to: feet)
            view.lift = lift
            return t < 0.16
        }
        var landing = windows.clampedFoot(feet)
        if landing.y - windows.floorY(near: landing) < 26 * ppp { landing.y = windows.floorY(near: landing) }
        if landing.distance(to: feet) > 0.5 {
            let from = feet
            var u: TimeInterval = 0
            try await windows.clock.run { dt in
                u = min(1, u + dt / 0.18)
                let e = CGFloat(1 - pow(1 - u, 3))
                windows.moveFoot(to: CGPoint(x: from.x + (landing.x - from.x) * e, y: from.y + (landing.y - from.y) * e))
                return u < 1
            }
        }
        view.lift = 0
        view.forceShadow = false
        windows.moveFoot(to: landing)
        cat.positions.saveNow(foot: landing)
        cat.personalityNudge(.curiosity, 0.002)

        if cat.library.has(.jump) {
            try await cat.animator.hold(.jump, frame: 3, for: 0.22, emotes: false)
        }
        try await recover(cat, wasAsleep: wasAsleep)
    }

    /// Cats land with dignity: a shake, a look around, maybe a quick groom.
    private func recover(_ cat: CatController, wasAsleep: Bool) async throws {
        if wasAsleep, cat.library.has(.confused) {
            cat.setState(.curious)
            try await cat.animator.play(Clips.confused)
            return
        }
        let enjoyedIt = cat.needs.affection > 0.65 && cat.personality.affection > 0.55 && Bool.random()
        if enjoyedIt {
            cat.setState(.happy)
            cat.emitHearts(count: 1)
            try await cat.animator.play(Clips.happy)
            return
        }
        if cat.library.has(.startled), Double.random(in: 0...1) < 0.5 {
            cat.setState(.surprised)
            try await cat.animator.play(Clips.startled)
        } else {
            cat.setState(.curious)
            try await cat.animator.play(Clips.lookAround)
        }
        if cat.library.has(.groom), Double.random(in: 0...1) < 0.4 {
            cat.setState(.grooming)
            try await cat.animator.loop(Clips.groom, for: 1.8)
        }
    }
}
