import AppKit
import SwiftUI

/// Everything the settings panes need.
struct SettingsDependencies {
    let settings: AppSettings
    let cat: CatController
    let loginItem: LaunchAtLoginManager
    let notifications: NotificationManager
    let audio: AudioManager
}

/// A classic macOS preferences window: toolbar tabs, each hosting a SwiftUI pane.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let dependencies: SettingsDependencies

    init(dependencies: SettingsDependencies) {
        self.dependencies = dependencies
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        let d = dependencies
        tabs.addTabViewItem(Self.tab("General", symbol: "gearshape", GeneralSettingsView(dependencies: d)))
        tabs.addTabViewItem(Self.tab("Appearance", symbol: "paintpalette", AppearanceSettingsView(settings: d.settings)))
        tabs.addTabViewItem(Self.tab("Behavior", symbol: "pawprint", BehaviorSettingsView(settings: d.settings, cat: d.cat)))
        tabs.addTabViewItem(Self.tab("Sound", symbol: "speaker.wave.2", SoundSettingsView(settings: d.settings, audio: d.audio)))
        tabs.addTabViewItem(Self.tab("Notifications", symbol: "bell.badge", NotificationSettingsView(settings: d.settings, notifications: d.notifications)))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("WhiskumiSettings")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func tab<Content: View>(_ title: String, symbol: String, _ content: Content) -> NSTabViewItem {
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.preferredContentSize]
        host.title = title
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    func present() {
        dependencies.loginItem.refresh()
        dependencies.notifications.refreshPermission()
        guard let window else { return }
        if !window.isVisible { window.center() }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
