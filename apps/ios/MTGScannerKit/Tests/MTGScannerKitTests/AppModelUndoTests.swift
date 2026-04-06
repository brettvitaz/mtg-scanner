import XCTest
@testable import MTGScannerKit

@MainActor
final class AppModelUndoTests: XCTestCase {
    func testConfirmUndoRunsLatestRegisteredActionOnly() {
        let model = AppModel()
        var firstRuns = 0
        var secondRuns = 0

        model.registerUndoAction { firstRuns += 1 }
        model.registerUndoAction { secondRuns += 1 }
        model.undoLatestDelete()
        model.confirmUndo()

        XCTAssertEqual(firstRuns, 0)
        XCTAssertEqual(secondRuns, 1)
    }

    func testConfirmUndoClearsActionAfterRunning() {
        let model = AppModel()
        var runs = 0

        model.registerUndoAction { runs += 1 }
        model.undoLatestDelete()
        model.confirmUndo()
        model.undoLatestDelete()
        model.confirmUndo()

        XCTAssertEqual(runs, 1)
    }

    func testUndoLatestDeleteSetsAlertFlagWhenActionExists() {
        let model = AppModel()
        model.registerUndoAction {}
        model.undoLatestDelete()
        XCTAssertTrue(model.showUndoAlert)
    }

    func testUndoLatestDeleteDoesNotSetAlertFlagWhenNoAction() {
        let model = AppModel()
        model.undoLatestDelete()
        XCTAssertFalse(model.showUndoAlert)
    }
}
