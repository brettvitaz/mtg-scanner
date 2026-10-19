import UIKit
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
        let zoom = app.buttons["capture-zoom-1"]
        for anchor in 1...3 { XCTAssertTrue(app.buttons["capture-zoom-\(anchor)"].exists) }
        screenshot("inline-zoom-running")
        zoom.tap()
        assertStatus("Ready")
        assertZoom(1, "1.5×")
        XCTAssertTrue(app.images["Last captured card"].exists)
        zoom.tap()
        assertZoom(1, "1×")
        for anchor in [2, 3, 1] {
            app.buttons["capture-zoom-\(anchor)"].tap()
            assertZoom(anchor, "\(anchor)×")
            app.buttons["capture-zoom-\(anchor)"].tap()
            assertZoom(anchor, "\(anchor).5×")
            app.buttons["capture-zoom-\(anchor)"].tap()
            assertZoom(anchor, "\(anchor)×")
        }
        XCTAssertEqual(app.buttons["station-start-stop"].label, "Stop Station")
        app.tabBars.buttons["Results"].tap()
        app.tabBars.buttons["Table"].tap()
        XCTAssertEqual(app.buttons["capture-zoom-1"].value as? String, "1×")
        app.tabBars.buttons["Station"].tap()
        assertStatus("Stopped")
        XCTAssertEqual(app.buttons["capture-zoom-1"].value as? String, "1×")
        screenshot("capture-navigation")
    }

    func testSecondaryActionGeometryIsFixedAcrossModesAndStationStates() {
        launch("capture-table-binder")
        let reference = app.buttons["Choose photo"].frame
        let shutter = app.buttons["capture-shutter"].frame
        let zoom = app.buttons["capture-zoom-1"].frame
        let navigation = app.tabBars.firstMatch.frame
        print("Capture spacing: zoom/shutter=\(shutter.minY - zoom.maxY), " +
              "shutter/tab=\(navigation.minY - shutter.maxY)")
        XCTAssertEqual(shutter.minY - zoom.maxY, 24, accuracy: 1)
        XCTAssertEqual(navigation.minY - shutter.maxY, 24, accuracy: 1)
        app.terminate()
        for state in ["ready", "settling", "capturing", "stopped", "paused"] {
            launch("capture-station-\(state)")
            let action = app.buttons["station-start-stop"].frame
            XCTAssertEqual(action.midX, reference.midX, accuracy: 1)
            XCTAssertEqual(action.midY, reference.midY, accuracy: 1)
            XCTAssertEqual(action.width, reference.width, accuracy: 1)
            XCTAssertEqual(action.height, reference.height, accuracy: 1)
            XCTAssertEqual(app.buttons["capture-shutter"].frame.midX, shutter.midX, accuracy: 1)
            XCTAssertEqual(app.buttons["capture-shutter"].frame.midY, shutter.midY, accuracy: 1)
            screenshot("fixed-action-\(state)")
            app.terminate()
        }
    }

    func testTableZoomIsRestoredAfterAStationRoundTrip() {
        launch("capture-table-binder")
        assertZoom(1, "1.5×")
        app.tabBars.buttons["Station"].tap()
        app.tabBars.buttons["Table"].tap()
        assertZoom(1, "1.5×")
        screenshot("table-half-step-after-mode-return")
        app.buttons["capture-zoom-1"].tap()
        assertZoom(1, "1×")
        screenshot("table-base-after-restored-zoom-tap")
    }

    func testThresholdFixturesKeepTheActiveValueOnTheShutterAxis() {
        for (route, anchor, value) in [("low", 1, "1.9×"), ("edge", 1, "1.9×"),
                                       ("high", 2, "2.1×"), ("upper", 3, "3.2×")] {
            launch("capture-zoom-pinch-\(route)")
            assertStatus("Ready")
            assertZoom(anchor, value)
            XCTAssertTrue(app.tabBars.buttons["Station"].isSelected)
            let active = app.buttons["capture-zoom-\(anchor)"]
            let shutter = app.buttons["capture-shutter"]
            XCTAssertEqual(active.frame.midX, shutter.frame.midX, accuracy: 1)
            for family in 1...3 {
                let button = app.buttons["capture-zoom-\(family)"]
                XCTAssertGreaterThanOrEqual(button.frame.width, 44)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            }
            app.tabBars.buttons["Station"].tap()
            assertZoom(anchor, value)
            screenshot("zoom-pinch-\(route)")
            active.tap()
            assertZoom(anchor, "\(anchor)×")
            app.terminate()
        }
    }

    func testMotionLocksCaptureAndStartButAllowsRetargeting() {
        launch("capture-station-zoom-transition")
        assertStatus("Paused")
        assertZoom(1, "1.5×")
        XCTAssertFalse(app.buttons["capture-shutter"].isEnabled)
        XCTAssertTrue(app.buttons["station-start-stop"].isEnabled)
        XCTAssertEqual(app.buttons["station-start-stop"].label, "Stop Station")
        screenshot("station-zoom-transition-locked")
        app.buttons["capture-zoom-2"].tap()
        assertZoom(2, "2×")
        XCTAssertTrue(app.buttons["station-start-stop"].isEnabled)
        XCTAssertTrue(app.buttons["capture-shutter"].isEnabled)
        assertStatus("Ready")
        XCTAssertEqual(app.buttons["station-start-stop"].label, "Stop Station")
        screenshot("post-zoom-ready-yellow-station")
        app.tabBars.buttons["Table"].tap()
        screenshot("table-selected-yellow")
    }

    func testNativePinchCrossesFamiliesAndCanReturnToBase() {
        launch("capture-zoom-open")
        assertZoom(1, "1.5×")
        app.images["capture-fixture-pinch-target"].pinch(withScale: 1.6, velocity: 1)
        let family = app.buttons["capture-zoom-3"]
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: family)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, app.debugDescription)
        screenshot("native-pinch-above-three")
        family.tap()
        assertZoom(3, "3×")
        app.images["capture-fixture-pinch-target"].pinch(withScale: 0.5, velocity: -1)
        let low = app.buttons["capture-zoom-1"]
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: low)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed, app.debugDescription)
        screenshot("native-pinch-reverse")
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
        let notification = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "capture-recognition-notice-")
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
        let failures = app.buttons["capture-recognition-queue"]
        XCTAssertTrue(failures.waitForExistence(timeout: 5))
        failures.tap()
        for action in ["Retry failed", "Dismiss failures"] { XCTAssertTrue(app.buttons[action].exists) }
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // Native popover presentation dismisses by tapping outside on iOS 26/iPad.
            app.images["capture-fixture-pinch-target"].tap()
        }
        failures.tap()
        app.buttons["Retry failed"].tap()
        XCTAssertTrue(failures.waitForExistence(timeout: 5))
        failures.tap()
        app.buttons["Dismiss failures"].tap()
        XCTAssertTrue(failures.waitForNonExistence(timeout: 5))
        XCTAssertTrue(captureRetry.exists)
        screenshot("capture-and-recognition-errors")
    }

    func testThreeNoticesDoNotMoveQueueOrCaptureControlsAndCancellationIsExplicit() {
        launch("capture-recognition-processing")
        let queue = app.buttons["capture-recognition-queue"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        XCTAssertEqual(queue.value as? String, "3 pending, 0 failed")
        let queueFrame = queue.frame
        let shutterFrame = app.buttons["capture-shutter"].frame
        screenshot("recognition-processing")
        app.terminate()
        launch("capture-recognition-stack")
        let notices = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "capture-recognition-notice-")
        )
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        XCTAssertEqual(notices.count, 3)
        XCTAssertFalse(app.buttons["Dismiss"].exists)
        XCTAssertFalse(app.buttons["Cancel recognition"].exists)
        XCTAssertEqual(queue.frame.midX, queueFrame.midX, accuracy: 1)
        XCTAssertEqual(queue.frame.midY, queueFrame.midY, accuracy: 1)
        XCTAssertEqual(app.buttons["capture-shutter"].frame.midY, shutterFrame.midY, accuracy: 1)
        XCTAssertLessThan(queue.frame.maxX, app.buttons["capture-shutter"].frame.minX)
        screenshot("recognition-three-notices")
        queue.tap()
        XCTAssertTrue(app.buttons["Cancel pending recognition"].waitForExistence(timeout: 3))
        screenshot("recognition-queue-actions")
        app.buttons["Cancel pending recognition"].tap()
        XCTAssertTrue(queue.waitForNonExistence(timeout: 5))
        XCTAssertEqual(notices.count, 3)
        XCTAssertEqual(app.buttons["capture-shutter"].frame.midY, shutterFrame.midY, accuracy: 1)
    }

    func testTabletOrientationKeepsControlsOnTheShutterAxis() throws {
        launch("capture-zoom-pinch-high")
        guard app.frame.width >= 700 else { throw XCTSkip("iPad orientation matrix runs on an iPad destination") }
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation != .portrait
            let viewport = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in (self.app.frame.width > self.app.frame.height) == landscape },
                object: app
            )
            XCTAssertEqual(XCTWaiter.wait(for: [viewport], timeout: 5), .completed)
            // Real actions wait for native idleness and prove the rotated controls are usable.
            app.buttons["capture-zoom-1"].tap()
            assertZoom(1, "1×")
            app.buttons["capture-zoom-2"].tap()
            assertZoom(2, "2×")
            assertStatus("Ready")
            XCTAssertEqual(app.buttons["capture-zoom-2"].frame.midX,
                           app.buttons["capture-shutter"].frame.midX, accuracy: 1)
            screenshot("tablet-orientation-\(orientation.rawValue)")
        }
    }

    func testLiveCameraRemainsConnectedAcrossCaptureModes() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Real preview verification requires a physical camera")
#else
        app.launchArguments = ["-UI_TEST_LIVE_CAMERA", "YES"]
        app.launch()
        let preview = app.otherElements["camera-live-preview"]
        for mode in ["Table", "Station", "Table", "Station", "Table"] {
            if app.alerts.buttons["OK"].exists { app.alerts.buttons["OK"].tap() }
            app.tabBars.buttons[mode].tap()
            XCTAssertTrue(preview.waitForExistence(timeout: 10))
            let live = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Live'"), object: preview)
            XCTAssertEqual(XCTWaiter.wait(for: [live], timeout: 5), .completed)
            XCTAssertTrue(preview.isHittable)
        }
#endif
    }

    private func launch(_ route: String) {
        app.launchArguments = ["-UI_PREVIEW_ROUTE", route]
        app.launch()
    }

    private func assertZoom(_ family: Int, _ value: String) {
        let control = app.buttons["capture-zoom-\(family)"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, app.debugDescription)
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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
