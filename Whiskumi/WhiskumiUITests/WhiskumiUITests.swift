//
//  WhiskumiUITests.swift
//  WhiskumiUITests
//
//  Created by Kőszegi Zoltán on 2026. 11. 07..
//

import XCTest

/// Smoke test: Whiskumi is a menu bar (agent) app whose only visible surface is a
/// transparent desktop panel, so UI testing is limited to launching and quitting cleanly.
/// Behaviour is covered by the unit tests and the DEBUG self-test (see README).
final class WhiskumiUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesAndKeepsRunning() throws {
        let app = XCUIApplication()
        app.launch()
        // Agent apps run without becoming frontmost; either running state is fine.
        let running = app.wait(for: .runningForeground, timeout: 5) || app.state == .runningBackground
        XCTAssertTrue(running)
        app.terminate()
    }
}
