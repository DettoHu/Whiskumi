import AppKit
import QuartzCore

/// A display-synchronised tick source for smooth motion (walking, carrying, the ball).
/// It only runs while something is moving; when every handler has finished it pauses,
/// so a resting cat costs no per-frame work at all.
final class FrameClock: NSObject {
    typealias Step = (TimeInterval) -> Bool

    private var handlers: [UUID: Step] = [:]
    private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?
    private var lastTimestamp: CFTimeInterval?
    private weak var hostView: NSView?

    func attach(to view: NSView) {
        hostView = view
        displayLink?.invalidate()
        displayLink = nil
        if !handlers.isEmpty { start() }
    }

    var isRunning: Bool { !handlers.isEmpty }

    /// Registers a per-frame step. The step returns `false` when it is done.
    @discardableResult
    func add(_ step: @escaping Step) -> UUID {
        let id = UUID()
        handlers[id] = step
        start()
        return id
    }

    func remove(_ id: UUID) {
        handlers[id] = nil
        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        }
        stopIfIdle()
    }

    /// Runs `step` every frame until it returns `false`. Throws `CancellationError` if the task is cancelled.
    func run(_ step: @escaping Step) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                continuations[id] = continuation
                handlers[id] = step
                start()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.remove(id) }
        }
    }

    private func start() {
        if displayLink == nil, fallbackTimer == nil {
            lastTimestamp = nil
            if let view = hostView, view.window != nil {
                let link = view.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            } else {
                let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick(timestamp: CACurrentMediaTime()) }
                }
                RunLoop.main.add(timer, forMode: .common)
                fallbackTimer = timer
            }
        }
        displayLink?.isPaused = false
    }

    private func stopIfIdle() {
        guard handlers.isEmpty else { return }
        displayLink?.isPaused = true
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        lastTimestamp = nil
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        tick(timestamp: link.timestamp)
    }

    private func tick(timestamp: CFTimeInterval) {
        let dt = lastTimestamp.map { (timestamp - $0).clamped(to: 0...0.05) } ?? (1.0 / 60.0)
        lastTimestamp = timestamp
        for (id, step) in handlers {
            // A handler may have been removed by an earlier one this tick.
            guard handlers[id] != nil else { continue }
            if !step(dt) {
                handlers[id] = nil
                continuations.removeValue(forKey: id)?.resume()
            }
        }
        stopIfIdle()
    }

    func invalidate() {
        for id in Array(handlers.keys) { remove(id) }
        displayLink?.invalidate()
        displayLink = nil
    }
}
