import AppKit
import SwiftUI

/// The menu bar item: left-click opens the status popover, right-click a compact menu.
final class MenuBarManager: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let cat: CatController
    private let settings: AppSettings
    private let actions: AppActions

    init(cat: CatController, settings: AppSettings, actions: AppActions) {
        self.cat = cat
        self.settings = settings
        self.actions = actions
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: MenuBarPopover(cat: cat, settings: settings, actions: actions))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    var isInstalled: Bool { statusItem != nil }

    func setVisible(_ visible: Bool) {
        visible ? install() : uninstall()
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "Whiskumi"
            button.setAccessibilityLabel("Whiskumi")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    private func uninstall() {
        popover.performClose(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePopover(sender)
        }
    }

    func togglePopover(_ sender: Any? = nil) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        guard let item = statusItem, let button = item.button else { return }
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(cat.isVisible ? "Hide Whiskumi" : "Show Whiskumi", symbol: cat.isVisible ? "eye.slash" : "eye",
                                     handler: actions.toggleCat))
        if cat.isVisible {
            menu.addItem(ClosureMenuItem("Pet", symbol: "hand.raised") { [cat] in cat.pet() })
            menu.addItem(CatContextMenu.behaviorMenuItem(settings: settings))
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", symbol: "gearshape", keyEquivalent: ",", handler: actions.openSettings))
        menu.addItem(ClosureMenuItem("Quit Whiskumi", symbol: "power", keyEquivalent: "q", handler: actions.quit))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    /// Hand focus back to whatever the user was doing, unless a Whiskumi window still needs it.
    func popoverDidClose(_ notification: Notification) {
        let hasOtherWindows = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        if !hasOtherWindows { NSApp.deactivate() }
    }

    func closePopover() {
        popover.performClose(nil)
    }

    var isPopoverShown: Bool { popover.isShown }
    var popoverView: NSView? { popover.contentViewController?.view }
    var statusButtonFrame: NSRect? { statusItem?.button?.window?.frame }
}
