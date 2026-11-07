import AppKit

/// Turns raw mouse input on and around the cat into intentions: pet, pick up,
/// open the quick-action bubble or context menu, and occasional cursor reactions.
final class CatInteractionHandler: DesktopCatViewDelegate {
    unowned let cat: CatController
    let drag: DragHandler
    let hud = InteractionHUD()
    var actions: AppActions

    private var petting = PettingHandler()
    private var pressPoint: CGPoint?
    private var dragging = false

    // Cursor reaction bookkeeping
    private var lastEvaluation: TimeInterval = 0
    private var lastDistance: CGFloat = .infinity
    private var hoverNearSince: Date?
    private var cooldowns: [String: Date] = [:]

    init(cat: CatController, actions: AppActions) {
        self.cat = cat
        self.actions = actions
        drag = DragHandler(cat: cat)
    }

    // MARK: - DesktopCatViewDelegate

    func catView(_ view: DesktopCatView, mouseDown event: NSEvent) {
        let point = NSEvent.mouseLocation
        guard cat.windows.isCatPixel(atScreenPoint: point, tolerance: 3) else { return }
        if event.clickCount >= 2 {
            pressPoint = nil
            hud.show(for: cat)
            return
        }
        hud.dismiss()
        pressPoint = point
        dragging = false
        cat.windows.forceInteractive = true
    }

    func catView(_ view: DesktopCatView, mouseDragged event: NSEvent) {
        guard let start = pressPoint else { return }
        let point = NSEvent.mouseLocation
        if !dragging, point.distance(to: start) > 4 {
            dragging = true
            drag.begin(at: start)
        }
        if dragging { drag.move(to: point, time: event.timestamp) }
    }

    func catView(_ view: DesktopCatView, mouseUp event: NSEvent) {
        defer {
            pressPoint = nil
            dragging = false
            if !drag.isCarrying { cat.windows.forceInteractive = false }
        }
        if dragging {
            drag.end()
            return
        }
        guard pressPoint != nil, event.clickCount <= 1 else { return }
        switch petting.registerClick(at: event.timestamp) {
        case .pet: cat.pet()
        case .overPetted: cat.overPetted()
        }
    }

    func catView(_ view: DesktopCatView, rightMouseDown event: NSEvent) {
        guard cat.windows.isCatPixel(atScreenPoint: NSEvent.mouseLocation, tolerance: 3) else { return }
        hud.dismiss()
        let menu = CatContextMenu.make(for: cat, actions: actions)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func catView(_ view: DesktopCatView, mouseMoved event: NSEvent) {
        let point = NSEvent.mouseLocation
        cat.windows.updateMouseTransparency(cursor: point)
        // Gentle stroking with the pointer counts as petting.
        guard pressPoint == nil, cat.windows.isCatPixel(atScreenPoint: point, tolerance: 1) else {
            petting.resetHover()
            return
        }
        if petting.registerHover(x: point.x, at: event.timestamp), cat.priority < .interaction || cat.state == .happy {
            cat.pet(intensity: 0.7)
        }
    }

    func catViewMouseExited(_ view: DesktopCatView) {
        petting.resetHover()
        cat.windows.updateMouseTransparency(cursor: NSEvent.mouseLocation)
    }

    // MARK: - Pointer anywhere on screen

    func pointerMoved(to point: CGPoint, velocity: CGVector) {
        guard cat.isVisible else { return }
        cat.windows.updateMouseTransparency(cursor: point)
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastEvaluation > 0.1 else { return }
        lastEvaluation = now
        evaluateReaction(point: point, velocity: velocity)
    }

    private func ready(_ key: String, cooldown: TimeInterval) -> Bool {
        if let last = cooldowns[key], Date().timeIntervalSince(last) < cooldown { return false }
        cooldowns[key] = Date()
        return true
    }

    private func evaluateReaction(point: CGPoint, velocity: CGVector) {
        let head = cat.windows.headPoint
        let distance = point.distance(to: head)
        defer { lastDistance = distance }
        guard cat.settings.cursorReactions, cat.canReact, !hud.isShown else {
            hoverNearSince = nil
            return
        }
        if cat.windows.isCatPixel(atScreenPoint: point) {
            hoverNearSince = nil
            return
        }
        let ppp = cat.windows.pointsPerPixel
        let speed = velocity.length
        let personality = cat.personality
        let roll = Double.random(in: 0...1)

        // A sudden flick right next to the cat.
        if speed > 2600, distance < 230 * ppp, ready("startle", cooldown: 25) {
            cat.reactStartled(from: point)
            return
        }
        // The pointer arrives nearby.
        let near = 150 * ppp
        if distance < near, lastDistance >= near, roll < 0.3 + personality.curiosity * 0.5, ready("curious", cooldown: 14) {
            cat.reactCurious(toward: point)
            return
        }
        // The pointer lingers close: bat at it.
        if distance < 120 * ppp {
            if let since = hoverNearSince {
                if Date().timeIntervalSince(since) > 1.6, cat.needs.energy > 0.3,
                   roll < 0.35 + personality.playfulness * 0.5, ready("bat", cooldown: 18) {
                    hoverNearSince = nil
                    cat.batAtCursor(point)
                    return
                }
            } else {
                hoverNearSince = Date()
            }
        } else {
            hoverNearSince = nil
        }
        // Now and then, a playful chase along the floor.
        let foot = cat.windows.foot
        let dx = abs(point.x - foot.x)
        if cat.settings.autonomousMovement, speed > 250, speed < 1400, abs(point.y - foot.y) < 140 * ppp,
           dx > 140 * ppp, dx < 600 * ppp, cat.needs.energy > 0.5,
           roll < 0.025 * personality.playfulness, ready("chase", cooldown: 75) {
            cat.chaseCursor(toX: point.x)
            return
        }
        // Otherwise just keep an eye on it.
        if distance < 520 * ppp, roll < 0.4 + personality.curiosity * 0.5, ready("glance", cooldown: 2.5) {
            cat.glance(toward: point)
        }
    }
}
