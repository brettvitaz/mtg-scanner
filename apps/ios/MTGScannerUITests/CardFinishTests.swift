import XCTest

@MainActor
final class CardFinishTests: XCTestCase {
    private let app = XCUIApplication()
    private let runID = UUID().uuidString

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEditFinishPersistsAfterRelaunch() {
        addTeardownBlock { @MainActor [app, runID] in
            XCTContext.runActivity(named: "Final screen, including failures") { activity in
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "workflow-end"
                screenshot.lifetime = .keepAlways
                activity.add(screenshot)
            }
            app.terminate()
            app.launchEnvironment["UI_TEST_RUN_ID"] = runID
            app.launchEnvironment["UI_TEST_MODE"] = "cleanup"
            app.launch()
            XCTAssertTrue(app.staticTexts["ui-test-cleanup"].waitForExistence(timeout: 10))
            app.terminate()
        }
        launch(mode: "fresh")
        openSavedCard()
        assertFinish("Non-foil")
        capture("initial-detail")

        app.buttons["card-detail-edit"].tap()
        let foil = app.switches["card-edit-foil"]
        XCTAssertTrue(foil.waitForExistence(timeout: 5))
        // The artwork section can leave Options below the visible editor area.
        app.collectionViews.firstMatch.swipeUp()
        XCTAssertTrue(foil.isHittable)
        XCTAssertEqual(foil.value as? String, "0")
        // SwiftUI exposes the whole row as a switch; its center is outside the thumb.
        foil.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: foil)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        capture("editor")
        app.buttons["card-edit-save"].tap()
        XCTAssertTrue(foil.waitForNonExistence(timeout: 5), "Save must dismiss the editor")
        assertFinish("Foil")
        capture("saved-detail")

        app.terminate()
        launch(mode: "resume")
        openSavedCard()
        assertFinish("Foil")
        capture("relaunched-detail")
    }

    private func launch(mode: String) {
        app.launchEnvironment["UI_TEST_RUN_ID"] = runID
        app.launchEnvironment["UI_TEST_MODE"] = mode
        app.launch()
    }

    private func openSavedCard() {
        let card = app.buttons["ui-test-saved-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["card-detail-edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Card Kingdom Prices"].waitForExistence(timeout: 5),
                      "The production price request must receive the offline fixture")
    }

    private func assertFinish(_ expected: String) {
        let finish = app.otherElements["card-detail-finish"]
        let predicate = NSPredicate(format: "value == %@", expected)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: finish)], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected saved finish \(expected); found \(finish.debugDescription)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
