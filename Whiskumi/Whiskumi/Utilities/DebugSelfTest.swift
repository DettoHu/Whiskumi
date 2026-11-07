#if DEBUG
import AppKit

/// Debug-only end-to-end exercise of the running app, for verifying behaviour on a machine
/// where screen capture isn't available. Launch with:
///
///     Whiskumi.app/Contents/MacOS/Whiskumi -WhiskumiSelfTest /path/to/output
///
/// It drives the real cat through its interactions, renders its own windows to PNG files,
/// and writes `report.txt` describing what it observed. It never runs unless asked.
enum DebugSelfTest {
    static var isRequested: Bool { UserDefaults.standard.string(forKey: "WhiskumiSelfTest") != nil }

    /// Self-tests never touch the real cat: settings and the save file live in throwaway locations.
    static func makeIsolatedEnvironment(library: SpriteLibrary) -> AppEnvironment {
        let suite = "dettohu.Whiskumi.selftest"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WhiskumiSelfTest-\(UUID().uuidString)")
        return AppEnvironment(library: library, defaults: defaults, persistence: PersistenceManager(directory: directory))
    }

    static func runIfRequested(_ environment: AppEnvironment) {
        guard let path = UserDefaults.standard.string(forKey: "WhiskumiSelfTest") else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        Task { @MainActor in
            await Runner(environment: environment, output: output).run()
        }
    }

    @MainActor
    private final class Runner {
        let env: AppEnvironment
        let output: URL
        var lines: [String] = []
        var failures = 0

        init(environment: AppEnvironment, output: URL) {
            env = environment
            self.output = output
        }

        var cat: CatController { env.cat }
        var windows: DesktopWindowManager { env.windows }

        func log(_ text: String) {
            lines.append(text)
            print("[SelfTest] \(text)")
        }

        func check(_ condition: Bool, _ label: String) {
            if !condition { failures += 1 }
            log("\(condition ? "PASS" : "FAIL") \(label)")
        }

        func wait(_ seconds: Double) async {
            try? await Task.sleep(for: .seconds(seconds))
        }

        func describe() -> String {
            let f = windows.window.frame
            return "state=\(cat.state.rawValue) posture=\(cat.posture) foot=(\(Int(windows.foot.x)),\(Int(windows.foot.y))) window=(\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height))) ppp=\(windows.pointsPerPixel)"
        }

        // MARK: Snapshots

        func snapshotCat(_ name: String) {
            let view = windows.catView
            let scale = view.window?.backingScaleFactor ?? 2
            let size = view.bounds.size
            guard size.width > 0, let layer = view.layer,
                  let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: scale, y: scale)
            // A desktop-like backdrop so transparency and edges are visible.
            context.setFillColor(CGColor(red: 0.27, green: 0.42, blue: 0.55, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(red: 0.33, green: 0.5, blue: 0.62, alpha: 1))
            for x in stride(from: 0, to: Int(size.width), by: 24) {
                for y in stride(from: 0, to: Int(size.height), by: 24) where (x / 24 + y / 24) % 2 == 0 {
                    context.fill(CGRect(x: x, y: y, width: 24, height: 24))
                }
            }
            context.interpolationQuality = .none
            layer.render(in: context)
            // The ball lives in its own window; draw it where it sits relative to the cat.
            if let ball = cat.play.ball, let ballLayer = ball.window.contentView?.layer {
                let offset = CGPoint(x: ball.window.frame.minX - windows.window.frame.minX, y: ball.window.frame.minY - windows.window.frame.minY)
                context.saveGState()
                context.translateBy(x: offset.x, y: offset.y)
                ballLayer.render(in: context)
                context.restoreGState()
            }
            if let image = context.makeImage() { write(image, name) }
        }

        func snapshotView(_ view: NSView?, _ name: String) {
            guard let view, view.bounds.width > 0,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                log("snapshot \(name): no view")
                return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: output.appendingPathComponent(name + ".png"))
            }
        }

        func write(_ image: CGImage, _ name: String) {
            let rep = NSBitmapImageRep(cgImage: image)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: output.appendingPathComponent(name + ".png"))
            }
        }

        // MARK: Script

        func run() async {
            log("Self-test starting. Sprites: \(env.library.animations.count) animations, \(env.library.props.count) props")
            await wait(2.5)
            log(describe())
            check(windows.isVisible, "cat window is visible")
            check(windows.window.level == .floating, "window level is floating (always on top)")
            check(windows.window.collectionBehavior.contains(.canJoinAllSpaces), "joins all Spaces")
            check(!windows.window.canBecomeKey, "cat window never takes keyboard focus")
            check(windows.window.backgroundColor == .clear && !windows.window.isOpaque, "window is transparent")
            snapshotCat("01_idle")

            // Click-through
            let corner = CGPoint(x: windows.window.frame.minX + 3, y: windows.window.frame.maxY - 3)
            windows.updateMouseTransparency(cursor: corner)
            check(windows.window.ignoresMouseEvents, "clicks pass through transparent corner")
            let body = CGPoint(x: windows.foot.x, y: windows.foot.y + 40 * windows.pointsPerPixel)
            windows.updateMouseTransparency(cursor: body)
            check(!windows.window.ignoresMouseEvents, "cat body receives clicks")
            windows.updateMouseTransparency(cursor: corner)

            // Petting
            let affectionBefore = cat.needs.affection
            cat.pet()
            await wait(0.5)
            log("after pet: " + describe())
            check(cat.state == .happy, "petting makes Whiskumi happy")
            check(cat.needs.affection > affectionBefore, "petting raises affection")
            snapshotCat("02_pet")
            await wait(3.5)

            // Feeding
            let fullnessBefore = cat.needs.fullness
            cat.feed(.salmonTreat)
            await wait(1.6)
            log("feeding: " + describe())
            check(cat.state == .eating || cat.state == .happy, "feeding starts eating")
            check(cat.needs.fullness > fullnessBefore, "feeding raises fullness")
            snapshotCat("03_eat")
            await wait(4)

            // Water
            let hydrationBefore = cat.needs.hydration
            cat.giveWater()
            await wait(1.2)
            check(cat.state == .drinking, "water starts drinking")
            check(cat.needs.hydration > hydrationBefore || hydrationBefore > 0.94, "water raises hydration")
            snapshotCat("04_drink")
            await wait(5.5)

            // Ball
            cat.startPlaying()
            check(cat.play.hasBall, "ball spawned")
            await wait(3)
            if let ball = cat.play.ball {
                log("ball at (\(Int(ball.position.x)),\(Int(ball.position.y))) moving=\(ball.isMoving); " + describe())
                check(ball.window.isVisible, "ball window visible")
                snapshotView(ball.window.contentView, "05_ball_view")
            }
            snapshotCat("05_play")
            await wait(6)
            log("after playing: " + describe())
            cat.putAwayBall()
            check(!cat.play.hasBall, "ball put away")
            await wait(1)

            // Sleep
            cat.letSleep()
            await wait(7)
            log("sleep: " + describe())
            check(cat.state == .sleeping, "let sleep → sleeping")
            snapshotCat("06_sleep")
            cat.wakeUp()
            await wait(3.5)
            log("woke: " + describe())
            check(cat.posture == .sitting, "wake up → sitting")

            // Carry: simulate a drag with real handler code
            if let interactions = env.interactions {
                let start = CGPoint(x: windows.foot.x, y: windows.foot.y + 40 * windows.pointsPerPixel)
                let before = windows.foot
                interactions.drag.begin(at: start)
                var time = ProcessInfo.processInfo.systemUptime
                for step in 1...30 {
                    try? await Task.sleep(for: .milliseconds(16))
                    time += 0.016
                    interactions.drag.move(to: CGPoint(x: start.x - CGFloat(step) * 9, y: start.y + CGFloat(step) * 6), time: time)
                }
                await wait(0.3)
                check(cat.state == .carried, "dragging carries the cat")
                snapshotCat("07_carried")
                interactions.drag.end()
                await wait(1.4)
                log("dropped: " + describe())
                check(windows.foot.distance(to: before) > 100, "cat moved with the drag")
                await wait(3)
            }

            // Activity gallery: every autonomous activity and cursor reaction, snapshotted mid-way.
            let gallery: [(String, CatActivity?, () -> Void)] = [
                ("curious", nil, { self.cat.reactCurious(toward: CGPoint(x: self.windows.foot.x + 200, y: self.windows.foot.y + 80)) }),
                ("startled", nil, { self.cat.reactStartled(from: CGPoint(x: self.windows.foot.x - 150, y: self.windows.foot.y + 60)) }),
                ("batCursor", nil, { self.cat.batAtCursor(CGPoint(x: self.windows.foot.x + 90, y: self.windows.foot.y + 40)) }),
                ("think", .think, {}), ("meow", .meow, {}), ("stretch", .stretch, {}), ("yawn", .yawn, {}),
                ("groom", .groom, {}), ("rollOver", .rollOver, {}), ("box", .box, {}), ("lookAround", .lookAround, {}),
                ("hop", .hop, {}), ("zoomies", .zoomies, {}), ("walk", .walk, {}),
            ]
            for (name, activity, start) in gallery {
                if let activity {
                    cat.perform(.interaction) { cat in try await cat.run(activity) }
                } else {
                    start()
                }
                await wait(name == "walk" || name == "zoomies" ? 0.6 : 1.1)
                log("\(name): " + describe())
                snapshotCat("12_\(name)")
                await wait(name == "box" ? 3 : 2.2)
            }
            cat.startLife()
            await wait(1.5)

            // Context menu
            let menu = CatContextMenu.make(for: cat, actions: AppActions(openSettings: {}, toggleCat: {}, quit: {}))
            let titles = menu.items.map(\.title).filter { !$0.isEmpty }
            log("context menu: " + titles.joined(separator: " | "))
            check(titles.contains("Pet") && titles.contains("Settings…") && titles.contains("Quit Whiskumi"), "context menu has core items")

            // Interaction HUD
            if let interactions = env.interactions {
                interactions.hud.show(for: cat)
                await wait(0.5)
                check(interactions.hud.isShown, "double-click bubble shows")
                snapshotView(interactions.hud.contentView, "08_hud")
                interactions.hud.dismiss()
            }

            // Menu bar popover
            if let menuBar = env.menuBar {
                check(menuBar.isInstalled, "menu bar item installed")
                menuBar.togglePopover()
                await wait(1.0)
                check(menuBar.isPopoverShown, "popover opens")
                snapshotView(menuBar.popoverView, "09_popover")
                menuBar.closePopover()
            }

            // Settings window, every tab
            if let controller = env.settingsWindow {
                controller.present()
                await wait(0.8)
                if let tabs = controller.window?.contentViewController as? NSTabViewController {
                    for index in tabs.tabViewItems.indices {
                        tabs.selectedTabViewItemIndex = index
                        await wait(0.7)
                        let size = controller.window?.frame.size ?? .zero
                        log("settings tab \(tabs.tabViewItems[index].label): \(Int(size.width))x\(Int(size.height))")
                        snapshotView(controller.window?.contentView?.superview ?? controller.window?.contentView, "10_settings_\(index)_\(tabs.tabViewItems[index].label)")
                    }
                    tabs.selectedTabViewItemIndex = 0
                }
                controller.window?.close()
            }

            // Settings persistence + live application
            let originalScale = env.settings.catScale
            env.settings.catScale = 1.5
            await wait(0.3)
            check(abs(windows.pointsPerPixel - 1.5) < 0.01, "size setting applied live")
            check(env.defaults.double(forKey: "catScale") == 1.5, "size setting persisted")
            snapshotCat("11_large")
            env.settings.catScale = originalScale
            env.settings.windowLayer = .desktop
            check(windows.window.level.rawValue < NSWindow.Level.normal.rawValue, "desktop window level applied")
            env.settings.windowLayer = .aboveAll

            // Hide / show
            env.toggleCat()
            await wait(0.4)
            check(!windows.isVisible && !cat.isVisible, "hide works")
            env.toggleCat()
            await wait(0.8)
            check(windows.isVisible && cat.isVisible, "show works")

            // Persistence
            cat.save()
            let saved = env.persistence.load()
            check(saved?.stats.pets ?? 0 >= 1 && saved?.stats.meals ?? 0 >= 1, "needs, personality and stats saved to disk")
            log("final: " + describe())
            log(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
            try? lines.joined(separator: "\n").write(to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            if UserDefaults.standard.bool(forKey: "WhiskumiSelfTestQuit") {
                NSApp.terminate(nil)
            }
        }
    }
}
#endif
