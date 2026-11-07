import AppKit

/// An `NSMenuItem` that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

/// Actions the app shell provides to menus (open settings, hide, quit).
struct AppActions {
    var openSettings: () -> Void
    var toggleCat: () -> Void
    var quit: () -> Void
}

/// Builds the right-click menu fresh each time so it only lists what makes sense right now.
enum CatContextMenu {
    static func make(for cat: CatController, actions: AppActions) -> NSMenu {
        let menu = NSMenu(title: "Whiskumi")
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Whiskumi · \(cat.mood.title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if cat.isSleeping {
            menu.addItem(ClosureMenuItem("Wake Up", symbol: "sun.max") { cat.wakeUp() })
            menu.addItem(ClosureMenuItem("Pet Gently", symbol: "hand.raised") { cat.pet(intensity: 0.6) })
        } else {
            menu.addItem(ClosureMenuItem("Pet", symbol: "hand.raised") { cat.pet() })
        }

        if cat.play.canPlay {
            if cat.play.hasBall {
                menu.addItem(ClosureMenuItem("Play with Ball", symbol: "circle.circle") {
                    cat.perform(.interaction) { cat in try await cat.play.playWithBall(userStarted: true) }
                })
                menu.addItem(ClosureMenuItem("Put Ball Away", symbol: "tray.and.arrow.down") { cat.putAwayBall() })
            } else {
                menu.addItem(ClosureMenuItem("Play", symbol: "circle.circle") { cat.startPlaying() })
            }
        }

        let foods = FoodItem.allCases.filter { cat.feeding.canEat($0) }
        if !foods.isEmpty {
            let feed = NSMenuItem(title: "Feed", action: nil, keyEquivalent: "")
            feed.image = NSImage(systemSymbolName: "fork.knife", accessibilityDescription: nil)
            let submenu = NSMenu()
            for food in foods {
                submenu.addItem(ClosureMenuItem(food.title, symbol: food.symbolName) { cat.feed(food) })
            }
            feed.submenu = submenu
            menu.addItem(feed)
        }

        if cat.feeding.canDrink {
            menu.addItem(ClosureMenuItem("Give Water", symbol: "drop") { cat.giveWater() })
        }

        if !cat.isSleeping, cat.library.has(.sleep) {
            menu.addItem(ClosureMenuItem("Let Sleep", symbol: "moon.zzz") { cat.letSleep() })
        }

        menu.addItem(.separator())
        menu.addItem(behaviorMenuItem(settings: cat.settings))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", symbol: "gearshape", handler: actions.openSettings))
        menu.addItem(ClosureMenuItem("Hide Whiskumi", symbol: "eye.slash", handler: actions.toggleCat))
        menu.addItem(ClosureMenuItem("Quit Whiskumi", symbol: "power", handler: actions.quit))
        return menu
    }

    static func behaviorMenuItem(settings: AppSettings) -> NSMenuItem {
        let item = NSMenuItem(title: "Change Behavior", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = settings.matchingPreset
        for preset in BehaviorPreset.allCases {
            let presetItem = ClosureMenuItem(preset.title) { settings.apply(preset) }
            presetItem.state = preset == current ? .on : .off
            presetItem.toolTip = preset.detail
            submenu.addItem(presetItem)
        }
        submenu.addItem(.separator())
        let reactions = ClosureMenuItem("React to Cursor") { settings.cursorReactions.toggle() }
        reactions.state = settings.cursorReactions ? .on : .off
        submenu.addItem(reactions)
        let random = ClosureMenuItem("Random Activities") { settings.randomActivities.toggle() }
        random.state = settings.randomActivities ? .on : .off
        submenu.addItem(random)
        item.submenu = submenu
        return item
    }
}
