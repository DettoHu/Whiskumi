import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    /// Unit tests load the app as a host; don't put a cat on the tester's desktop.
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var terminationSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else { return }
        installTerminationHandler()
        do {
            let library = try SpriteLibrary()
            let environment: AppEnvironment
            #if DEBUG
            environment = DebugSelfTest.isRequested ? DebugSelfTest.makeIsolatedEnvironment(library: library) : AppEnvironment(library: library)
            #else
            environment = AppEnvironment(library: library)
            #endif
            self.environment = environment
            MainMenu.install(openSettings: { [weak environment] in environment?.openSettings() })
            environment.start()
        } catch {
            Log.app.fault("Startup failed: \(error.localizedDescription, privacy: .public)")
            NSApp.activate()
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Whiskumi couldn't find its artwork"
            alert.informativeText = "\(error.localizedDescription)\n\nPlease reinstall Whiskumi, or rebuild it from the project."
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// A plain SIGTERM (e.g. `kill`) still goes through a normal quit, so Whiskumi's state is saved.
    private func installTerminationHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSource = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.shutdown()
    }

    /// Opening the app again (Finder, Launchpad, Spotlight) brings the cat back and shows settings,
    /// so Whiskumi stays reachable even with the menu bar icon turned off.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment?.handleReopen()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
