import XCTest

@MainActor
final class CaptureControlsTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }

    func testFiveTabsZoomPauseExplicitResumeAndSameTabReselect() {
        launch("capture-station-ready")
        for title in ["Table", "Station", "Results", "Library", "Settings"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists)
        }
        assertStatus("Ready")
        app.tabBars.buttons["Station"].tap()
        assertStatus("Ready")
        XCTAssertEqual(app.sheets.count, 0)
        let zoom = app.buttons["capture-zoom"]
        zoom.tap()
        XCTAssertTrue(app.buttons["1.5×"].waitForExistence(timeout: 3))
        for choice in ["1×", "1.5×", "2×", "3×"] { XCTAssertTrue(app.buttons[choice].exists) }
        XCTAssertEqual(app.descendants(matching: .any)["station-status"].value as? String, "Ready")
        screenshot("zoom-menu-running")
        app.buttons["1.5×"].tap()
        assertStatus("Paused")
        XCTAssertEqual(zoom.value as? String, "1.5×")
        XCTAssertTrue(app.images["Last captured card"].exists)
        for choice in ["3×", "2×", "1×"] {
            zoom.tap()
            app.buttons[choice].tap()
            XCTAssertEqual(zoom.value as? String, choice)
        }
        app.buttons["station-start-stop"].tap()
        assertStatus("Ready")
        app.tabBars.buttons["Results"].tap()
        app.tabBars.buttons["Table"].tap()
        XCTAssertEqual(app.buttons["capture-zoom"].value as? String, "1×")
        app.tabBars.buttons["Station"].tap()
        assertStatus("Stopped")
        XCTAssertEqual(app.buttons["capture-zoom"].value as? String, "1×")
        screenshot("capture-navigation")
    }

    func testTorchHoldPresetRelativeDragCloseAndRestore() {
        launch("capture-table-binder")
        let torch = app.buttons["capture-torch"]
        XCTAssertTrue(torch.waitForExistence(timeout: 5))
        torch.press(forDuration: 0.7)
        let bar = app.otherElements["torch-brightness-bar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), app.debugDescription)
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        assertPercentage("25%")
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        let end = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.63, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        assertPercentage("48%")
        screenshot("brightness-relative-48")
        app.buttons["Close"].tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 3))
        torch.tap()
        XCTAssertEqual(torch.value as? String, "Off")
        torch.tap()
        XCTAssertEqual(torch.value as? String, "On at 48 percent")
    }

    func testStationFixturesSurviveAppearanceAndSelectedTabReselect() {
        for (suffix, expected) in [("ready", "Ready"), ("settling", "Settling"), ("capturing", "Capturing"),
                                   ("stopped", "Stopped"), ("error", "Paused"), ("paused", "Paused")] {
            launch("capture-station-\(suffix)")
            assertStatus(expected)
            XCTAssertTrue(app.tabBars.buttons["Station"].isSelected)
            app.tabBars.buttons["Station"].tap()
            assertStatus(expected)
            screenshot("station-\(suffix)")
            app.terminate()
        }
    }

    func testRecognitionPreferencePreservesThumbnail() {
        launch("capture-recognition-foil")
        let notification = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Recognized Lightning Bolt")
        ).firstMatch
        XCTAssertTrue(notification.waitForExistence(timeout: 5))
        screenshot("recognition-foil")
        app.terminate()
        launch("capture-recognition-disabled")
        XCTAssertFalse(notification.exists)
        XCTAssertTrue(app.images["Last captured card"].exists)
        screenshot("recognition-disabled")
    }

    func testCaptureAndRecognitionErrorsExposeDistinctRetryControls() {
        launch("capture-station-error")
        let captureRetry = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Capture failed.")
        ).firstMatch
        XCTAssertTrue(captureRetry.waitForExistence(timeout: 5))
        let failures = app.buttons["Recognition failures"]
        XCTAssertTrue(failures.waitForExistence(timeout: 5))
        failures.tap()
        for action in ["Retry", "Dismiss", "Cancel"] { XCTAssertTrue(app.alerts.buttons[action].exists) }
        app.alerts.buttons["Cancel"].tap()
        failures.tap()
        app.alerts.buttons["Retry"].tap()
        XCTAssertTrue(failures.waitForExistence(timeout: 5))
        failures.tap()
        app.alerts.buttons["Dismiss"].tap()
        XCTAssertTrue(failures.waitForNonExistence(timeout: 5))
        XCTAssertTrue(captureRetry.exists)
        screenshot("capture-and-recognition-errors")
    }

    private func launch(_ route: String) {
        app.launchArguments = ["-UI_PREVIEW_ROUTE", route]
        app.launch()
    }

    private func assertStatus(_ value: String) {
        let status = app.descendants(matching: .any)["station-status"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, app.debugDescription)
    }

    private func assertPercentage(_ value: String) {
        let bar = app.otherElements["torch-brightness-bar"]
        let expected = value.replacingOccurrences(of: "%", with: " percent")
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: bar)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 3), .completed, app.debugDescription)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
