//
//  NativeDictateUITests.swift
//  FlowDictateUITests
//
//  Created by Frank Euler on 16.08.26.
//

import XCTest

final class NativeDictateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMenuBarApplicationLaunches() throws {
        let app = XCUIApplication()
        app.launchEnvironment["NATIVEDICTATE_UI_TESTING"] = "1"
        app.launchEnvironment["OPENAI_API_KEY"] = "ui-test-key"
        if app.state != .notRunning {
            app.terminate()
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10) || app.state == .runningBackground)
        app.terminate()
    }
}
