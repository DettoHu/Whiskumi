//
//  WhiskumiApp.swift
//  Whiskumi
//
//  Created by Kőszegi Zoltán on 2026. 11. 07..
//

import AppKit

/// Whiskumi is an AppKit agent app: no Dock icon, a menu bar item, and a cat on the desktop.
/// The SwiftUI `App` lifecycle is not used because every window here is custom
/// (a transparent desktop panel, a status popover and a toolbar-style settings window).
@main
enum WhiskumiApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
