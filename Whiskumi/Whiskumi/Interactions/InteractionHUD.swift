import AppKit
import SwiftUI

/// A hosting view that responds to the very first click, even though its panel never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The small quick-action bubble that appears above Whiskumi on double-click.
final class InteractionHUD {
    private let panel: TransparentPanel
    private var monitors: [Any] = []
    private var dismissTask: Task<Void, Never>?
    private weak var cat: CatController?

    init() {
        panel = TransparentPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120))
        panel.ignoresMouseEvents = false
    }

    var isShown: Bool { panel.isVisible }
    var contentView: NSView? { panel.contentView }
    var frame: NSRect { panel.frame }

    func show(for cat: CatController) {
        self.cat = cat
        let view = InteractionHUDView(cat: cat) { [weak self] in self?.dismiss() }
        let host = FirstMouseHostingView(rootView: view)
        host.sizingOptions = [.intrinsicContentSize]
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.level = cat.windows.window.level == .normal ? .floating : cat.windows.window.level
        panel.collectionBehavior = cat.windows.window.collectionBehavior

        let head = cat.windows.headPoint
        let visible = cat.windows.screens.visibleFrame(near: head)
        var origin = CGPoint(x: head.x - size.width / 2, y: head.y + 36 * cat.windows.pointsPerPixel)
        if origin.y + size.height > visible.maxY { origin.y = cat.windows.foot.y - size.height - 8 }
        origin.x = origin.x.clamped(to: visible.minX + 6...max(visible.minX + 6, visible.maxX - size.width - 6))
        origin.y = origin.y.clamped(to: visible.minY + 4...max(visible.minY + 4, visible.maxY - size.height - 4))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        installMonitors()
        scheduleAutoDismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        removeMonitors()
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    private func installMonitors() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.dismiss()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            if let self, event.window !== self.panel { self.dismiss() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}

private struct InteractionHUDView: View {
    let cat: CatController
    let dismiss: () -> Void
    @State private var showingFood = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                if cat.isSleeping {
                    HUDButton(title: "Wake", symbol: "sun.max.fill") { act { cat.wakeUp() } }
                } else {
                    HUDButton(title: "Pet", symbol: "hand.raised.fill") { act { cat.pet() } }
                }
                if cat.feeding.canFeed {
                    HUDButton(title: "Feed", symbol: "fork.knife", isActive: showingFood) {
                        withAnimation(.snappy(duration: 0.2)) { showingFood.toggle() }
                    }
                }
                if cat.feeding.canDrink {
                    HUDButton(title: "Water", symbol: "drop.fill") { act { cat.giveWater() } }
                }
                if cat.play.canPlay {
                    HUDButton(title: "Play", symbol: "circle.circle.fill") { act { cat.startPlaying() } }
                }
                if !cat.isSleeping, cat.library.has(.sleep) {
                    HUDButton(title: "Sleep", symbol: "moon.zzz.fill") { act { cat.letSleep() } }
                }
            }
            if showingFood {
                HStack(spacing: 6) {
                    ForEach(FoodItem.allCases.filter { cat.feeding.canEat($0) }) { food in
                        Button {
                            act { cat.feed(food) }
                        } label: {
                            Label(food.title, systemImage: food.symbolName)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .padding(8)
        .fixedSize()
    }

    private func act(_ action: () -> Void) {
        action()
        dismiss()
    }
}

private struct HUDButton: View {
    let title: String
    let symbol: String
    var isActive = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(isActive || hovering ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.07))
                    )
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
