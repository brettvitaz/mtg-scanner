import XCTest

@MainActor
final class PriceFilterNavigationTests: XCTestCase {
    func testToolbarCommitsNavigatesAndBlocksInvalidCompletion() {
        continueAfterFailure = false
        let app = launch("pricing-filter-editing")
        defer { app.terminate() }
        let minimum = app.textFields["Min Retail"]
        XCTAssertTrue(minimum.waitForExistence(timeout: 5))
        XCTAssertEqual(minimum.value as? String, ".50")
        XCTAssertFalse(app.buttons["price-previous"].isEnabled)
        app.buttons["price-next"].tap()
        XCTAssertEqual(minimum.value as? String, "0.50")
        let maximum = app.textFields["Max Retail"]
        maximum.typeText("1.2.3")
        app.buttons["price-keyboard-done"].tap()
        XCTAssertTrue(error(in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(maximum.value as? String, "1.2.3")
        maximum.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "2")
        app.buttons["price-previous"].tap()
        XCTAssertEqual(maximum.value as? String, "2.00")
        app.buttons["price-next"].tap()
        app.buttons["price-next"].tap()
        app.buttons["price-next"].tap()
        XCTAssertFalse(app.buttons["price-next"].isEnabled)
        app.buttons["price-keyboard-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    }

    func testSheetDoneValidatesResetClearsAndReopeningLoadsCommittedValues() {
        continueAfterFailure = false
        let app = launch("pricing-results")
        defer { app.terminate() }
        let minimum = openFilter(in: app)
        minimum.tap()
        minimum.typeText("1.2.3")
        app.buttons["price-filter-done"].tap()
        XCTAssertTrue(error(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["price-filter-done"].exists)
        minimum.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + ".50")
        app.buttons["price-filter-done"].tap()
        XCTAssertTrue(app.buttons["price-filter-done"].waitForNonExistence(timeout: 3))
        let reopened = openFilter(in: app)
        XCTAssertEqual(reopened.value as? String, "0.50")
        app.buttons["price-filter-reset"].tap()
        XCTAssertEqual(reopened.value as? String, "Any")
        XCTAssertFalse(error(in: app).exists)
        app.buttons["price-filter-done"].tap()
        XCTAssertTrue(app.buttons["price-filter-done"].waitForNonExistence(timeout: 3))
    }

    func testFirstSeparatorAndHardwareReturn() {
        continueAfterFailure = false
        let app = launch("pricing-filter")
        defer { app.terminate() }
        let minimum = revealMinimum(in: app)
        minimum.tap()
        minimum.typeText(".")
        XCTAssertEqual(minimum.value as? String, ".")
        minimum.typeText("50\n")
        XCTAssertEqual(minimum.value as? String, "0.50")
        app.textFields["Max Retail"].typeText("2\n")
        app.textFields["Min Buylist"].typeText("1\n")
        app.textFields["Max Buylist"].typeText("3\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Max Buylist"].value as? String, "3.00")
    }

    func testEachClearButtonEmptiesOnlyItsFieldAndKeepsEditing() {
        continueAfterFailure = false
        let app = launch("pricing-filter-editing")
        defer { app.terminate() }
        let labels = ["Min Retail", "Max Retail", "Min Buylist", "Max Buylist"]
        for (index, label) in labels.enumerated() {
            let field = app.textFields[label]
            if index > 0 { field.typeText("2") }
            let clear = app.buttons["Clear " + label]
            XCTAssertTrue(clear.waitForExistence(timeout: 3))
            clear.tap()
            XCTAssertEqual(field.value as? String, "Any")
            XCTAssertTrue(clear.waitForNonExistence(timeout: 3))
            field.typeText("3")
            XCTAssertEqual(field.value as? String, "3")
            XCTAssertTrue(clear.exists)
            if index < 3 { app.buttons["price-next"].tap() }
        }
        XCTAssertEqual(app.textFields["Min Retail"].value as? String, "3.00")
        XCTAssertEqual(app.textFields["Max Retail"].value as? String, "3.00")
        XCTAssertEqual(app.textFields["Min Buylist"].value as? String, "3.00")
    }

    func testClearRemovesInvalidDraftErrorAndKeepsKeyboardOpen() {
        continueAfterFailure = false
        let app = launch("pricing-filter-invalid")
        defer { app.terminate() }
        XCTAssertTrue(error(in: app).waitForExistence(timeout: 5))
        app.buttons["Clear Min Retail"].tap()
        XCTAssertTrue(error(in: app).waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Min Retail"].value as? String, "Any")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.textFields["Min Retail"].typeText(".50")
        XCTAssertEqual(app.textFields["Min Retail"].value as? String, ".50")
    }

    func testClearingAnotherFieldMovesEditingToThatField() {
        continueAfterFailure = false
        let app = launch("pricing-filter-editing")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["price-next"].waitForExistence(timeout: 5))
        app.buttons["price-next"].tap()
        app.textFields["Max Retail"].typeText("2")
        app.buttons["price-next"].tap()
        app.buttons["Clear Max Retail"].tap()
        app.textFields["Max Retail"].typeText("4")
        XCTAssertEqual(app.textFields["Max Retail"].value as? String, "4")
        XCTAssertEqual(app.textFields["Min Retail"].value as? String, "0.50")
    }

    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_PREVIEW_ROUTE", route]
        app.launch()
        return app
    }

    private func openFilter(in app: XCUIApplication) -> XCUIElement {
        let filter = app.buttons["Filter cards"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.buttons["price-filter-done"].waitForExistence(timeout: 5))
        return revealMinimum(in: app)
    }

    private func revealMinimum(in app: XCUIApplication) -> XCUIElement {
        let minimum = app.textFields["Min Retail"]
        for _ in 0..<8 {
            if minimum.isHittable { return minimum }
            app.swipeUp()
        }
        XCTFail("Min Retail did not become visible")
        return minimum
    }

    private func error(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Enter a valid price.")).firstMatch
    }
}
