import AppKit

/// The ball game: spawn the toy, let Whiskumi notice it, chase it and bat it around.
final class PlayHandler {
    unowned let cat: CatController
    private(set) var ball: BallToy?
    private var despawnTask: Task<Void, Never>?

    init(cat: CatController) {
        self.cat = cat
    }

    var hasBall: Bool { ball != nil }

    var canPlay: Bool { cat.library.prop("ball") != nil && cat.library.has(.playBall) }

    func spawnBall() {
        guard ball == nil, canPlay, let image = cat.library.prop("ball") else { return }
        let windows = cat.windows
        let toy = BallToy(image: image, clock: windows.clock, screens: windows.screens,
                          pointsPerPixel: windows.pointsPerPixel, renderQuality: cat.settings.renderQuality)
        let foot = windows.foot
        let range = windows.walkableRange(near: foot)
        let side = cat.facing
        let dropX = (foot.x + side.sign * 90 * windows.pointsPerPixel).clamped(to: range)
        toy.floorY = foot.y
        toy.place(at: CGPoint(x: dropX, y: foot.y + 90 * windows.pointsPerPixel))
        toy.show(matching: windows.window)
        toy.kick(CGVector(dx: side.sign * 60, dy: 80))
        toy.onThrown = { [weak self] in self?.userMovedBall() }
        toy.onPoked = { [weak self] in self?.userMovedBall() }
        ball = toy
        cat.ballOut = true
        scheduleDespawnCheck()
    }

    func removeBall(animated: Bool) {
        despawnTask?.cancel()
        despawnTask = nil
        ball?.remove(animated: animated)
        ball = nil
        cat.ballOut = false
    }

    func screensChanged() {
        ball?.screensChanged()
    }

    /// A thrown or poked ball is irresistible — unless Whiskumi is busy with something you asked for.
    private func userMovedBall() {
        guard cat.isVisible, cat.priority != .carried else { return }
        if cat.state == .playing || cat.state == .chasing { return }
        cat.perform(.interaction) { cat in try await cat.play.playWithBall(userStarted: true) }
    }

    /// Untouched balls tidy themselves away after a couple of quiet minutes.
    private func scheduleDespawnCheck() {
        despawnTask?.cancel()
        despawnTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, let ball = self.ball else { return }
                let quiet = Date().timeIntervalSince(ball.lastTouched)
                let playing = self.cat.state == .playing || self.cat.state == .chasing
                if quiet > 150, !playing, !ball.isHeld {
                    self.removeBall(animated: true)
                    return
                }
            }
        }
    }

    // MARK: - Play script

    func playWithBall(userStarted: Bool = false) async throws {
        guard ball != nil else { return }
        try await cat.getUpIfNeeded()
        cat.setState(.playing)
        cat.recordStat { $0.playSessions += 1 }
        cat.personalityNudge(.playfulness, userStarted ? 0.004 : 0.001)
        if let ball {
            cat.facing = .toward(dx: ball.position.x - cat.windows.foot.x)
            if userStarted {
                try await cat.animator.play(.pose(cat.library.has(.curious) ? .curious : .idle, for: 0.7))
            }
        }
        var rounds = Int.random(in: 2...4) + Int((cat.personality.playfulness * 3).rounded())
        if cat.needs.energy < 0.3 { rounds = min(rounds, 2) }
        while rounds > 0, let ball {
            try await waitUntilSettled(ball)
            guard self.ball === ball else { return }
            try await approach(ball)
            try await bat(ball)
            cat.mutateNeeds { $0.play(intensity: 0.5) }
            rounds -= 1
        }
        cat.setState(.happy)
        if let ball { cat.facing = .toward(dx: ball.position.x - cat.windows.foot.x) }
        try await cat.animator.play(Clips.contentSmile)
    }

    private func waitUntilSettled(_ ball: BallToy) async throws {
        var waited: TimeInterval = 0
        cat.animator.show(.idle)
        while (ball.isMoving || ball.isHeld) && waited < 8 {
            cat.facing = .toward(dx: ball.position.x - cat.windows.foot.x)
            try await Task.sleep(for: .seconds(0.12))
            waited += 0.12
        }
    }

    /// Horizontal distance from the cat's anchor to the ball's centre when batting it, from the art.
    private func contactDistance() -> CGFloat {
        let ppp = cat.windows.pointsPerPixel
        guard let data = cat.library.animation(.playBall),
              let placement = data.frameProps.first(where: { $0.prop == "ball" && $0.frame == 0 }),
              let image = cat.library.prop("ball") else { return 38 * ppp }
        return abs(placement.origin.x + CGFloat(image.width) / 2 - data.anchor.x) * ppp
    }

    private func approach(_ ball: BallToy) async throws {
        let windows = cat.windows
        let contact = contactDistance()
        var foot = windows.foot
        if abs(ball.position.y - foot.y) > 6 {
            // The ball is on another ledge: pounce over to it.
            let side = Facing.toward(dx: ball.position.x - foot.x)
            let landX = ball.position.x - side.sign * contact
            try await cat.jump(by: CGVector(dx: landX - foot.x, dy: ball.position.y - foot.y))
            foot = windows.foot
        }
        ball.floorY = foot.y
        let side = Facing.toward(dx: ball.position.x - foot.x)
        let target = ball.position.x - side.sign * contact
        let distance = abs(target - foot.x)
        if distance > 4 * windows.pointsPerPixel {
            let sprint = distance > 110 * windows.pointsPerPixel
            try await cat.walk(toX: target, speed: sprint ? 150 : 62, clip: sprint ? Clips.run : Clips.walk, as: .chasing)
        }
        cat.facing = .toward(dx: ball.position.x - cat.windows.foot.x)
        cat.setState(.playing)
    }

    private func bat(_ ball: BallToy) async throws {
        guard let data = cat.library.animation(.playBall), let image = cat.library.prop("ball") else { return }
        let windows = cat.windows
        let ppp = windows.pointsPerPixel
        let flipped = cat.facing != data.facing
        for step in Clips.batBall.frames {
            cat.animator.show(.playBall, frame: step.index)
            if step.index < 2, let placement = data.frameProps.first(where: { $0.prop == "ball" && $0.frame == step.index }) {
                // The ball sits under the paw exactly where the artist drew it.
                var dx = placement.origin.x + CGFloat(image.width) / 2 - data.anchor.x
                if flipped { dx = -dx }
                let lift = max(0, data.anchor.y - (placement.origin.y + CGFloat(image.height)))
                ball.place(at: CGPoint(x: windows.foot.x + dx * ppp, y: windows.foot.y + lift * ppp))
            }
            if step.index == 2 {
                let power = CGFloat.random(in: 230...430) * (0.6 + cat.personality.playfulness * 0.8)
                ball.kick(CGVector(dx: cat.facing.sign * power, dy: CGFloat.random(in: 120...320)))
                cat.audio.play(.play)
            }
            try await Task.sleep(for: .seconds(step.duration / max(0.1, cat.animator.speed)))
        }
        cat.animator.show(.idle)
    }
}
