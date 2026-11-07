import AppKit

/// Composition root: builds every subsystem, wires them together and routes settings changes.
final class AppEnvironment {
    let defaults: UserDefaults
    let settings: AppSettings
    let persistence: PersistenceManager
    let screens = ScreenManager()
    let loginItem = LaunchAtLoginManager()
    let mouse = MouseTracker()
    let library: SpriteLibrary
    let positions: WindowPositionManager
    let audio: AudioManager
    let notifications: NotificationManager
    let windows: DesktopWindowManager
    let cat: CatController

    private(set) var interactions: CatInteractionHandler?
    private(set) var menuBar: MenuBarManager?
    private(set) var settingsWindow: SettingsWindowController?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(library: SpriteLibrary, defaults: UserDefaults = .standard, persistence: PersistenceManager = PersistenceManager()) {
        self.library = library
        self.defaults = defaults
        self.persistence = persistence
        settings = AppSettings(defaults: defaults)
        positions = WindowPositionManager(screens: screens, defaults: defaults)
        audio = AudioManager(settings: settings)
        notifications = NotificationManager(settings: settings, defaults: defaults)
        windows = DesktopWindowManager(library: library, screens: screens)
        cat = CatController(settings: settings, library: library, windows: windows, audio: audio,
                            persistence: persistence, positions: positions)

        let actions = AppActions(
            openSettings: { [weak self] in self?.openSettings() },
            toggleCat: { [weak self] in self?.toggleCat() },
            quit: { NSApp.terminate(nil) }
        )
        let interactions = CatInteractionHandler(cat: cat, actions: actions)
        windows.catView.delegate = interactions
        self.interactions = interactions
        menuBar = MenuBarManager(cat: cat, settings: settings, actions: actions)
        settingsWindow = SettingsWindowController(dependencies: SettingsDependencies(
            settings: settings, cat: cat, loginItem: loginItem, notifications: notifications, audio: audio
        ))
    }

    func start() {
        windows.apply(settings)
        cat.start(visible: settings.showCatOnLaunch)
        updateMenuBarVisibility()

        mouse.onMove = { [weak self] point, velocity in
            self?.interactions?.pointerMoved(to: point, velocity: velocity)
        }
        mouse.start()
        screens.onScreensChanged = { [weak self] in self?.cat.screensChanged() }
        settings.addObserver { [weak self] key in self?.settingChanged(key) }
        cat.onNeedsTick = { [weak self] needs in self?.notifications.evaluate(needs) }
        #if DEBUG
        DebugSelfTest.runIfRequested(self)
        #endif

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cat.tick()
                self?.cat.screensChanged()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cat.save() }
        })
    }

    func shutdown() {
        mouse.stop()
        cat.shutdown()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    // MARK: - Actions

    func toggleCat() {
        if cat.isVisible {
            interactions?.hud.dismiss()
            cat.hide()
        } else {
            cat.show()
        }
        updateMenuBarVisibility()
    }

    func openSettings() {
        menuBar?.closePopover()
        interactions?.hud.dismiss()
        settingsWindow?.present()
    }

    func handleReopen() {
        if !cat.isVisible {
            cat.show()
            updateMenuBarVisibility()
        }
        if !settings.showMenuBarIcon { openSettings() }
    }

    /// The menu bar icon can be turned off, but never while the cat is hidden — otherwise
    /// there would be no way back to Whiskumi.
    private func updateMenuBarVisibility() {
        menuBar?.setVisible(settings.showMenuBarIcon || !cat.isVisible)
    }

    private func settingChanged(_ key: AppSettings.Key) {
        switch key {
        case .windowLayer, .showOnAllDesktops, .catSize, .renderQuality, .visualEffects, .groundShadow,
             .animationSpeed, .randomActivities, .autonomousMovement:
            cat.applySettings()
        case .showMenuBarIcon:
            updateMenuBarVisibility()
        case .defaultPosition:
            if !settings.restorePosition, !cat.isVisible { cat.placeInitially() }
        default:
            break
        }
    }
}
