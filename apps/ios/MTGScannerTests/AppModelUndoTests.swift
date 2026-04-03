import XCTest
@testable import MTGScanner

@MainActor
final class AppModelUndoTests: XCTestCase {
    func testUndoLatestDeleteRunsLatestRegisteredActionOnly() {
        let model = AppModel()
        var firstRuns = 0
        var secondRuns = 0

        model.registerUndoAction { firstRuns += 1 }
        model.registerUndoAction { secondRuns += 1 }
        model.undoLatestDelete()

        XCTAssertEqual(firstRuns, 0)
        XCTAssertEqual(secondRuns, 1)
    }

    func testUndoLatestDeleteClearsActionAfterRunning() {
        let model = AppModel()
        var runs = 0

        model.registerUndoAction { runs += 1 }
        model.undoLatestDelete()
        model.undoLatestDelete()

        XCTAssertEqual(runs, 1)
    }
}
