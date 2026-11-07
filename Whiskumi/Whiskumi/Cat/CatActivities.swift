import AppKit

/// The activity scripts. Each is a plain `async` function built from animation clips,
/// waits and movement; cancellation (an interaction, a drag, hiding) stops it mid-frame.
extension CatController {
    // MARK: - Resting and posture

    func idle(for duration: TimeInterval) async throws {
        try await getUpIfNeeded()
        setState(.idle)
        animator.show(.idle, frame: 0)
        let end = Date().addingTimeInterval(duration)
        while Date() < end {
            try await Task.sleep(for: .seconds(Double.random(in: 2.2...5.0)))
            let roll = Double.random(in: 0...1)
            if needs.energy < 0.3, roll < 0.45 {
                try await animator.play(Clips.slowBlink)
            } else if roll < 0.1, needs.affection > 0.45 {
                try await animator.play(Clips.slowBlink)
            } else if roll < 0.2, needs.happiness > 0.6 {
                try await animator.play(Clips.contentSmile)
            } else if roll < 0.28 {
                try await animator.play(Clips.idleShift)
            } else {
                try await animator.play(Clips.blink)
            }
        }
    }

    /// Brings the cat back to a sitting pose from wherever it is, quickly.
    func getUpIfNeeded() async throws {
        switch posture {
        case .sitting:
            return
        case .sleeping, .lying:
            try await wake(fully: false)
        case .inBox:
            setState(.playing)
            windows.catView.forceShadow = true
            defer { windows.catView.forceShadow = false }
            try await animator.play(.timed(.jump, [(1, 0.14), (2, 0.16), (3, 0.2)]))
            posture = .sitting
            animator.show(.idle)
        }
    }

    func wake(fully: Bool) async throws {
        guard posture == .sleeping || posture == .lying else { return }
        if posture == .sleeping {
            setState(.lyingDown)
            try await animator.hold(.sleep, frame: 0, for: fully ? 0.6 : 0.25)
        }
        if library.has(.lieDown) {
            try await animator.play(Clips.getUp)
        }
        posture = .sitting
        if fully {
            if library.has(.stretch), Bool.random() {
                setState(.stretching)
                try await animator.play(Clips.stretch)
            } else if library.has(.yawn) {
                setState(.yawning)
                try await animator.play(Clips.yawn)
            }
        }
        setState(.idle)
        animator.show(.idle)
    }

    func run(_ activity: CatActivity) async throws {
        // Every activity starts from sitting, except a nap, which may continue from lying down.
        if !(activity == .nap && posture == .lying) {
            try await getUpIfNeeded()
        }
        switch activity {
        case .idle:
            try await idle(for: Double.random(in: 4...8))
        case .lookAround:
            setState(.curious)
            try await animator.play(Clips.lookAround)
        case .stretch:
            setState(.stretching)
            try await animator.play(Clips.stretch)
        case .groom:
            setState(.grooming)
            try await animator.loop(Clips.groom, for: Double.random(in: 3...6))
            try await animator.play(Clips.contentSmile)
        case .sit:
            setState(.sitting)
            try await animator.hold(.sit, for: Double.random(in: 4...9))
        case .lieDown:
            try await lieDownAndRest()
        case .nap:
            try await nap(encouraged: false)
        case .walk:
            try await wander()
        case .yawn:
            setState(.yawning)
            try await animator.play(Clips.yawn)
        case .meow:
            setState(.meowing)
            audio.play(.meow)
            try await animator.play(Clips.meow)
        case .rollOver:
            setState(.rolling)
            try await animator.play(Clips.rollOver)
        case .box:
            try await boxTime()
        case .think:
            setState(.thinking)
            try await animator.play(Clips.think)
            if needs.fullness < 0.35 || needs.hydration < 0.35, library.has(.meow) {
                setState(.meowing)
                audio.play(.meow)
                try await animator.play(Clips.meow)
            }
        case .hop:
            try await hop()
        case .zoomies:
            try await zoomies()
        }
    }

    private func lieDownAndRest() async throws {
        setState(.lyingDown)
        try await animator.play(Clips.lieDown)
        posture = .lying
        try await animator.hold(.lieDown, frame: 2, for: Double.random(in: 6...14))
        let sleepChance = personality.laziness * 0.4 * (0.4 + settings.sleepFrequency * 1.2)
        if needs.energy < 0.45 || Double.random(in: 0...1) < sleepChance {
            try await nap(encouraged: false)
        } else {
            try await wake(fully: false)
        }
    }

    /// Yawn, curl up and sleep until rested (or for a while).
    func nap(encouraged: Bool) async throws {
        try await getUpIfNeededForSleep()
        if posture != .lying && posture != .sleeping {
            if library.has(.yawn) {
                setState(.yawning)
                try await animator.play(Clips.yawn)
            }
            setState(.lyingDown)
            try await animator.play(Clips.lieDown)
            posture = .lying
        }
        if encouraged { personalityNudge(.laziness, 0.003) }
        let base = encouraged ? 600.0 : Double.random(in: 150...480) * (0.5 + settings.sleepFrequency)
        try await sleep(maxDuration: max(60, base))
        try await wake(fully: true)
    }

    private func getUpIfNeededForSleep() async throws {
        if posture == .inBox { try await getUpIfNeeded() }
    }

    private func sleep(maxDuration: TimeInterval) async throws {
        posture = .sleeping
        setState(.sleeping)
        recordStat { $0.naps += 1 }
        audio.play(.sleep)
        let start = Date()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in try await self?.emitZs() }
            while true {
                try await animator.play(Clips.breathe)
                let elapsed = Date().timeIntervalSince(start)
                if elapsed > maxDuration || (needs.energy > 0.97 && elapsed > 45) { break }
            }
            group.cancelAll()
        }
    }

    private func emitZs() async throws {
        let props = ["zSmall", "zMedium", "zLarge"]
        while true {
            for (i, prop) in props.enumerated() {
                let head = headParticleOrigin()
                windows.catView.emitParticle(
                    prop,
                    offset: CGPoint(x: head.x + 8 + CGFloat(i) * 5, y: head.y + 2 + CGFloat(i) * 7),
                    drift: CGVector(dx: 12 + CGFloat(i) * 3, dy: 24 + CGFloat(i) * 4),
                    duration: 2.6,
                    scale: (0.7, 1.15)
                )
                try await Task.sleep(for: .seconds(1.05))
            }
            try await Task.sleep(for: .seconds(2.6))
        }
    }

    private func boxTime() async throws {
        setState(.hiding)
        posture = .inBox
        try await animator.play(Clips.boxSettle)
        let end = Date().addingTimeInterval(Double.random(in: 6...14))
        while Date() < end {
            try await animator.play(Clips.boxDoze)
            if Bool.random() {
                let head = headParticleOrigin()
                windows.catView.emitParticle("zSmall", offset: CGPoint(x: head.x + 10, y: head.y + 2),
                                             drift: CGVector(dx: 12, dy: 22), duration: 2.2)
            }
        }
        try await getUpIfNeeded()
    }

    // MARK: - Movement

    /// A short stroll: one to three legs, pausing to look around in between.
    private func wander() async throws {
        try await getUpIfNeeded()
        let segments = Int.random(in: 1...3)
        for leg in 0..<segments {
            let range = windows.walkableRange(near: windows.foot)
            guard range.upperBound - range.lowerBound > 40 else { return }
            let distance = CGFloat.random(in: 70...300) * windows.pointsPerPixel
            let foot = windows.foot
            var direction: Facing = Double.random(in: 0...1) < 0.65 ? facing : facing.opposite
            if foot.x - distance < range.lowerBound { direction = .right }
            if foot.x + distance > range.upperBound { direction = .left }
            let target = (foot.x + direction.sign * distance).clamped(to: range)
            try await walk(toX: target)
            if leg < segments - 1 {
                if Bool.random(), library.has(.lookAround) {
                    setState(.curious)
                    try await animator.play(Clips.glance)
                } else {
                    try await idle(for: Double.random(in: 1.2...2.5))
                }
            }
        }
    }

    /// Walks (or runs) horizontally to `target`, animating and moving in lockstep.
    func walk(toX target: CGFloat, speed: CGFloat = 44, clip: AnimationClip = Clips.walk, as newState: CatState = .walking) async throws {
        try await getUpIfNeeded()
        let range = windows.walkableRange(near: windows.foot)
        let target = target.clamped(to: range)
        let dx = target - windows.foot.x
        guard abs(dx) > 2 else { return }
        facing = .toward(dx: dx)
        setState(newState)
        activityLevel = 1
        defer {
            activityLevel = 0
            positions.save(foot: windows.foot)
        }
        let y = windows.foot.y
        let animator = self.animator
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in try await animator.loop(clip) }
            try await windows.clock.run { [weak self] dt in
                guard let self else { return false }
                let step = speed * self.windows.pointsPerPixel * CGFloat(dt * self.animator.speed)
                let remaining = target - self.windows.foot.x
                if abs(remaining) <= step {
                    self.windows.moveFoot(to: CGPoint(x: target, y: y))
                    return false
                }
                self.windows.moveFoot(to: CGPoint(x: self.windows.foot.x + (remaining > 0 ? step : -step), y: y))
                return true
            }
            group.cancelAll()
        }
        animator.show(.idle)
    }

    /// A pounce along an arc from the current feet position by (dx, dy) points.
    func jump(by offset: CGVector) async throws {
        let start = windows.foot
        let end = windows.clampedFoot(start + offset)
        if abs(end.x - start.x) > 1 { facing = .toward(dx: end.x - start.x) }
        try await animator.hold(.jump, frame: 0, for: 0.2)
        windows.catView.forceShadow = true
        defer { windows.catView.forceShadow = false }
        let duration = (0.38 + Double(abs(end.y - start.y)) / 900) / max(0.5, animator.speed)
        let peak = 10 * windows.pointsPerPixel + max(0, end.y - start.y) * 0.35
        var t = 0.0
        animator.show(.jump, frame: 1)
        var showedSecond = false
        try await windows.clock.run { [weak self] dt in
            guard let self else { return false }
            t = min(1, t + dt / duration)
            if t > 0.5, !showedSecond {
                showedSecond = true
                self.animator.show(.jump, frame: 2)
            }
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t + 4 * peak * t * (1 - t)
            self.windows.moveFoot(to: CGPoint(x: x, y: y))
            return t < 1
        }
        try await animator.hold(.jump, frame: 3, for: 0.22)
        positions.save(foot: windows.foot)
        animator.show(.idle)
    }

    private func hop() async throws {
        try await getUpIfNeeded()
        setState(.playing)
        let distance = settings.autonomousMovement ? CGFloat.random(in: 18...46) * windows.pointsPerPixel : 0
        try await jump(by: CGVector(dx: facing.sign * distance, dy: 0))
    }

    /// A sudden burst of running, as cats do.
    private func zoomies() async throws {
        try await getUpIfNeeded()
        let range = windows.walkableRange(near: windows.foot)
        let foot = windows.foot
        let roomRight = range.upperBound - foot.x
        let roomLeft = foot.x - range.lowerBound
        let direction: Facing = roomRight > roomLeft ? .right : .left
        let distance = min(max(roomRight, roomLeft), CGFloat.random(in: 160...420) * windows.pointsPerPixel)
        guard distance > 60 else { return }
        try await walk(toX: foot.x + direction.sign * distance, speed: 165, clip: Clips.run, as: .playing)
        if library.has(.excited), Bool.random() {
            setState(.happy)
            try await animator.play(Clips.excited)
        }
    }

    // MARK: - Greeting

    func greet() async throws {
        if isFirstLaunchGreeting {
            setState(.happy)
            audio.play(.meow)
            try await animator.play(library.has(.excited) ? Clips.excited : Clips.happy)
            emitHearts(count: 3)
            try await animator.play(Clips.contentSmile)
        } else if awayLongEnoughForGreeting {
            setState(.yawning)
            try await animator.play(Clips.yawn)
            setState(.meowing)
            audio.play(.meow)
            try await animator.play(Clips.meow)
            if needs.affection > 0.5 { emitHearts(count: 2) }
        }
    }

    // MARK: - Petting

    func receivePets(intensity: Double) async throws {
        let wasAsleep = posture == .sleeping
        try await getUpIfNeeded()
        mutateNeeds { $0.receivePets(intensity: intensity) }
        recordStat { $0.pets += 1 }
        personalityNudge(.affection, 0.003 * intensity)
        audio.play(.purr)
        setState(.happy)
        emitHearts(count: intensity > 0.8 ? 2 : 1)
        if wasAsleep {
            try await animator.play(Clips.slowBlink)
        }
        let enthusiasm = (needs.affection + personality.affection) / 2
        let loving = library.has(.heart) && Double.random(in: 0...1) < enthusiasm * 0.8
        try await animator.play(loving ? Clips.heart : Clips.happy)
        try await animator.play(Clips.contentSmile)
    }

    func reactToOverPetting() async throws {
        try await getUpIfNeeded()
        if personality.affection < 0.55, library.has(.angry) {
            setState(.surprised)
            try await animator.play(Clips.angry)
            setState(.grooming)
            try await animator.loop(Clips.groom, for: 1.5)
        } else {
            setState(.happy)
            emitHearts(count: 3)
            try await animator.play(Clips.excited)
            if library.has(.rollOver) {
                setState(.rolling)
                try await animator.play(Clips.rollOver)
            }
        }
    }

    // MARK: - Cursor reactions

    func reactCurious(toward point: CGPoint) {
        perform(.reaction) { cat in
            cat.facing = .toward(dx: point.x - cat.windows.foot.x)
            cat.setState(.curious)
            try await cat.animator.play(Clips.curious)
            cat.personalityNudge(.curiosity, 0.0015)
        }
    }

    func reactStartled(from point: CGPoint) {
        perform(.reaction) { cat in
            cat.facing = .toward(dx: point.x - cat.windows.foot.x)
            cat.setState(.surprised)
            try await cat.animator.play(cat.library.has(.startled) ? Clips.startled : Clips.surprised)
            try await cat.animator.play(Clips.glance)
        }
    }

    func batAtCursor(_ point: CGPoint) {
        perform(.reaction) { cat in
            cat.facing = .toward(dx: point.x - cat.windows.foot.x)
            cat.setState(.playing)
            try await cat.animator.play(Clips.playCursor)
            cat.mutateNeeds { $0.play(intensity: 0.3) }
            cat.personalityNudge(.playfulness, 0.002)
        }
    }

    func chaseCursor(toX x: CGFloat) {
        perform(.reaction) { cat in
            cat.setState(.chasing)
            let foot = cat.windows.foot
            let reach = 40 * cat.windows.pointsPerPixel
            let target = x - Facing.toward(dx: x - foot.x).sign * reach
            try await cat.walk(toX: target, speed: 150, clip: Clips.run, as: .chasing)
            let pointer = NSEvent.mouseLocation
            cat.facing = .toward(dx: pointer.x - cat.windows.foot.x)
            if pointer.distance(to: cat.windows.headPoint) > 220 * cat.windows.pointsPerPixel, cat.library.has(.confused) {
                // The pointer got away.
                cat.setState(.curious)
                try await cat.animator.play(Clips.confused)
                return
            }
            try await cat.animator.play(Clips.playCursor)
            cat.mutateNeeds { $0.play(intensity: 0.5) }
            cat.personalityNudge(.playfulness, 0.003)
        }
    }

    /// Turns to face the pointer without interrupting anything.
    func glance(toward point: CGPoint) {
        guard state == .idle || state == .sitting, posture == .sitting, priority == .autonomous else { return }
        let desired = Facing.toward(dx: point.x - windows.foot.x)
        if desired != facing { facing = desired }
    }
}

extension CatController {
    fileprivate var isFirstLaunchGreeting: Bool { stats.pets == 0 && stats.meals == 0 && Date().timeIntervalSince(stats.adoptedOn) < 120 }
    fileprivate var awayLongEnoughForGreeting: Bool { awayTime > 30 * 60 }
}
