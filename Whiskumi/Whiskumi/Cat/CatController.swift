import AppKit
import Observation
import os

/// Who gets to drive the cat. Higher priorities interrupt lower ones.
enum ActivityPriority: Int, Comparable {
    case autonomous, reaction, interaction, carried

    static func < (lhs: ActivityPriority, rhs: ActivityPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A snapshot of the frame on screen, mirrored into the menu bar preview.
struct PreviewFrame {
    let image: CGImage
    let flipped: Bool
    /// Head-centre x and ground line y in canvas pixels (top-left origin).
    let anchor: CGPoint
}

/// Whiskumi's brain. It owns the needs/personality model and runs exactly one
/// activity script at a time. Scripts are `async` functions; replacing the current
/// script cancels it at its next frame, so every animation is safely interruptible.
@Observable
final class CatController {
    typealias Script = @MainActor (CatController) async throws -> Void

    // MARK: Observable state

    private(set) var state: CatState = .idle
    private(set) var needs: CatNeeds
    private(set) var personality: CatPersonality
    private(set) var stats: CatStats
    private(set) var isVisible = false
    private(set) var preview: PreviewFrame?
    /// Whether the toy ball is out (mirrored here so SwiftUI can observe it).
    var ballOut = false

    var mood: CatMood { CatMood.evaluate(needs: needs, state: state) }

    // MARK: Collaborators

    let settings: AppSettings
    let library: SpriteLibrary
    let windows: DesktopWindowManager
    let animator: SpriteAnimationController
    let audio: AudioManager
    let positions: WindowPositionManager
    private let persistence: PersistenceManager

    @ObservationIgnored private(set) var feeding: FeedingHandler!
    @ObservationIgnored private(set) var play: PlayHandler!

    // MARK: Runner

    @ObservationIgnored private var engine = CatBehaviorEngine()
    @ObservationIgnored private var activityTask: Task<Void, Never>?
    @ObservationIgnored private var activityToken = 0
    @ObservationIgnored private(set) var priority: ActivityPriority = .autonomous
    var posture: Posture = .sitting
    @ObservationIgnored var activityLevel: Double = 0

    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored let awayTime: TimeInterval
    @ObservationIgnored private let isFirstLaunch: Bool

    /// Called after every needs update (used for gentle reminders).
    @ObservationIgnored var onNeedsTick: ((CatNeeds) -> Void)?

    var facing: Facing {
        get { animator.facing }
        set { animator.facing = newValue }
    }

    init(settings: AppSettings, library: SpriteLibrary, windows: DesktopWindowManager, audio: AudioManager,
         persistence: PersistenceManager, positions: WindowPositionManager) {
        self.settings = settings
        self.library = library
        self.windows = windows
        self.audio = audio
        self.persistence = persistence
        self.positions = positions
        animator = SpriteAnimationController(library: library)

        let saved = persistence.load()
        var data = saved ?? CatSaveData()
        if let saved {
            data.needs.applyOfflineTime(Date().timeIntervalSince(saved.savedAt))
        }
        needs = data.needs
        personality = data.personality
        stats = data.stats
        awayTime = saved.map { Date().timeIntervalSince($0.savedAt) } ?? 0
        isFirstLaunch = saved == nil

        feeding = FeedingHandler(cat: self)
        play = PlayHandler(cat: self)
        animator.renderer = windows.catView
        animator.speed = settings.animationSpeed
        animator.onFrameChange = { [weak self] data, frame, facing in
            self?.preview = PreviewFrame(image: data.frame(at: frame).image, flipped: facing != data.facing, anchor: data.anchor)
        }
        if isFirstLaunch { save() }
    }

    // MARK: - Lifecycle

    func start(visible: Bool) {
        startHeartbeat()
        placeInitially()
        animator.show(.idle)
        if visible { show(greet: true) }
    }

    func show(greet: Bool = false) {
        guard !isVisible else { return }
        isVisible = true
        windows.moveFoot(to: windows.clampedFoot(windows.foot))
        windows.show()
        posture = .sitting
        animator.show(.idle)
        startLife(greeting: greet)
    }

    func hide() {
        guard isVisible else { return }
        cancelActivity()
        play.removeBall(animated: false)
        windows.hide()
        isVisible = false
        setState(.idle)
        positions.saveNow(foot: windows.foot)
        save()
    }

    func shutdown() {
        cancelActivity()
        heartbeat?.cancel()
        play.removeBall(animated: false)
        positions.saveNow(foot: windows.foot)
        save()
    }

    func placeInitially() {
        let restored = settings.restorePosition ? positions.restoredFoot() : nil
        let foot = restored ?? positions.defaultFoot(settings.defaultPosition)
        windows.moveFoot(to: windows.clampedFoot(foot))
    }

    func resetPosition() {
        let foot = positions.defaultFoot(settings.defaultPosition)
        if isVisible {
            perform(.interaction) { cat in
                try await cat.getUpIfNeeded()
                cat.windows.moveFoot(to: cat.windows.clampedFoot(foot))
                try await cat.animator.play(Clips.lookAround)
            }
        } else {
            windows.moveFoot(to: windows.clampedFoot(foot))
        }
        positions.saveNow(foot: windows.clampedFoot(foot))
    }

    /// Displays were added, removed or rearranged.
    func screensChanged() {
        windows.recomputeLayout()
        windows.moveFoot(to: windows.clampedFoot(windows.foot))
        play.screensChanged()
        if isVisible && priority != .carried { startLife() }
    }

    // MARK: - Running scripts

    /// Replaces the current activity with `script`, unless something more important is happening.
    @discardableResult
    func perform(_ newPriority: ActivityPriority, _ script: @escaping Script) -> Bool {
        guard isVisible else { return false }
        if priority == .carried && newPriority != .carried { return false }
        if newPriority == .reaction && priority > .autonomous { return false }
        activityToken += 1
        let token = activityToken
        let previous = activityTask
        previous?.cancel()
        priority = newPriority
        activityTask = Task { [weak self] in
            // Let the interrupted script unwind (its `defer`s run) before taking over.
            await previous?.value
            guard let self, !Task.isCancelled, self.activityToken == token else { return }
            do {
                try await script(self)
            } catch {
                // Cancelled: whoever replaced us is in charge now.
            }
            guard self.activityToken == token, self.isVisible else { return }
            self.priority = .autonomous
            self.startLife()
        }
        return true
    }

    func startLife(greeting: Bool = false) {
        priority = .autonomous
        perform(.autonomous) { cat in
            if greeting { try await cat.greet() }
            try await cat.lifeLoop()
        }
    }

    func cancelActivity() {
        activityToken += 1
        activityTask?.cancel()
        activityTask = nil
        priority = .autonomous
        activityLevel = 0
    }

    var isBusyWithUser: Bool { priority >= .interaction }

    /// Cursor reactions only interrupt a cat that is sitting around on its own.
    var canReact: Bool {
        isVisible && priority == .autonomous && posture == .sitting && state != .walking && state != .playing
    }

    // MARK: - Autonomous life

    private func lifeLoop() async throws {
        while true {
            try await idle(for: nextIdleInterval())
            if play.hasBall, needs.energy > 0.25, Double.random(in: 0...1) < 0.35 + personality.playfulness * 0.4 {
                try await play.playWithBall()
                continue
            }
            let activity = engine.choose(behaviorContext())
            Log.behavior.debug("Activity: \(activity.rawValue, privacy: .public)")
            try await run(activity)
        }
    }

    private func behaviorContext() -> BehaviorContext {
        var context = BehaviorContext()
        context.needs = needs
        context.personality = personality
        context.walkingFrequency = settings.walkingFrequency
        context.sleepFrequency = settings.sleepFrequency
        context.randomActivities = settings.randomActivities
        context.autonomousMovement = settings.autonomousMovement
        context.available = Set(CatActivity.allCases.filter { $0.requiredAnimations.allSatisfy(library.has) })
        context.hour = Calendar.current.component(.hour, from: Date())
        return context
    }

    /// Seconds of quiet sitting between activities; "Activity frequency" shortens or stretches it.
    private func nextIdleInterval() -> TimeInterval {
        Double.random(in: 7...15) * (1.7 - 1.3 * settings.activityFrequency)
    }

    // MARK: - Helpers used by scripts and handlers

    func setState(_ newState: CatState) {
        if state != newState { state = newState }
    }

    func mutateNeeds(_ body: (inout CatNeeds) -> Void) {
        body(&needs)
    }

    func recordStat(_ body: (inout CatStats) -> Void) {
        body(&stats)
    }

    func personalityNudge(_ trait: CatPersonality.Trait, _ amount: Double) {
        personality.nudge(trait, by: amount)
    }

    func applySettings() {
        animator.speed = settings.animationSpeed
        windows.apply(settings)
        windows.moveFoot(to: windows.clampedFoot(windows.foot))
        if !settings.autonomousMovement || !settings.randomActivities, isVisible, priority == .autonomous {
            startLife()
        }
    }

    /// Head-top position relative to the feet in source pixels, nudged toward the face.
    func headParticleOrigin() -> CGPoint {
        let head = animator.headOffset()
        return CGPoint(x: 10, y: head.y - 6)
    }

    func emitHearts(count: Int) {
        let origin = headParticleOrigin()
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.isVisible else { return }
                    self.windows.catView.emitParticle(
                        "heartSmall",
                        offset: CGPoint(x: origin.x + CGFloat.random(in: -14...16), y: origin.y + CGFloat.random(in: 0...8)),
                        drift: CGVector(dx: CGFloat.random(in: -8...10), dy: CGFloat.random(in: 22...34)),
                        duration: 1.5
                    )
                }
            }
        }
    }

    // MARK: - Persistence

    private func startHeartbeat() {
        heartbeat?.cancel()
        lastTick = Date()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self else { return }
                self.tick()
            }
        }
    }

    func tick() {
        let now = Date()
        // Long gaps (system sleep) count like offline time: partially, never harshly.
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now
        if elapsed > 900 {
            needs.applyOfflineTime(elapsed)
        } else {
            needs.advance(by: elapsed, sleeping: state == .sleeping, activity: activityLevel)
        }
        onNeedsTick?(needs)
        if now.timeIntervalSince(lastSave) > 120 { save() }
    }

    func save() {
        let data = CatSaveData(needs: needs, personality: personality, stats: stats, savedAt: Date())
        do {
            try persistence.save(data)
        } catch {
            Log.persistence.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
        lastSave = Date()
    }

    /// Starts over with a brand-new kitten (needs, personality and stats).
    func resetCat() {
        needs = CatNeeds()
        personality = .newborn()
        stats = CatStats()
        save()
        if isVisible { startLife(greeting: true) }
    }

    // MARK: - Public actions (menus, popover, interaction HUD)

    var isSleeping: Bool { posture == .sleeping }

    func pet(intensity: Double = 1) {
        perform(.interaction) { cat in try await cat.receivePets(intensity: intensity) }
    }

    func overPetted() {
        perform(.interaction) { cat in try await cat.reactToOverPetting() }
    }

    func feed(_ food: FoodItem) {
        guard feeding.canEat(food) else { return }
        perform(.interaction) { cat in try await cat.feeding.eat(food) }
    }

    func giveWater() {
        guard feeding.canDrink else { return }
        perform(.interaction) { cat in try await cat.feeding.drink() }
    }

    func letSleep() {
        guard library.has(.sleep) || library.has(.lieDown) else { return }
        perform(.interaction) { cat in try await cat.nap(encouraged: true) }
    }

    func wakeUp() {
        perform(.interaction) { cat in
            try await cat.wake(fully: true)
            try await cat.animator.play(Clips.happy)
        }
    }

    func startPlaying() {
        play.spawnBall()
        perform(.interaction) { cat in try await cat.play.playWithBall(userStarted: true) }
    }

    func putAwayBall() {
        let wasPlaying = state == .playing || state == .chasing
        play.removeBall(animated: true)
        if wasPlaying, library.has(.sad) {
            perform(.interaction) { cat in
                try await cat.getUpIfNeeded()
                cat.setState(.sitting)
                try await cat.animator.play(Clips.sad)
            }
        }
    }

    func meow() {
        perform(.interaction) { cat in
            try await cat.getUpIfNeeded()
            cat.setState(.meowing)
            cat.audio.play(.meow)
            try await cat.animator.play(Clips.meow)
        }
    }
}
