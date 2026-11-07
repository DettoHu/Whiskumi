import AppKit

/// Follows the pointer anywhere on screen (no special permissions are needed for mouse
/// movement), and reports position plus a smoothed velocity.
final class MouseTracker {
    var onMove: ((CGPoint, CGVector) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastPoint: CGPoint?
    private var lastTime: TimeInterval = 0
    private(set) var velocity: CGVector = .zero
    private(set) var location: CGPoint = NSEvent.mouseLocation

    func start() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    /// Lets views that receive the events directly (tracking areas) feed the same pipeline.
    func feed(_ event: NSEvent) {
        handle(event)
    }

    private func handle(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        let now = event.timestamp
        if let last = lastPoint, now > lastTime {
            let dt = now - lastTime
            if dt < 0.25 {
                let instant = CGVector(dx: (point.x - last.x) / dt, dy: (point.y - last.y) / dt)
                let k = smoothing(rate: 18, dt: dt)
                velocity = CGVector(dx: velocity.dx + (instant.dx - velocity.dx) * k,
                                    dy: velocity.dy + (instant.dy - velocity.dy) * k)
            } else {
                velocity = .zero
            }
        }
        lastPoint = point
        lastTime = now
        location = point
        onMove?(point, velocity)
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
