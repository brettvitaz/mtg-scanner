import XCTest
@testable import MTGScannerKit

final class CardDetectionEngineTests: XCTestCase {

    func testUpdateDetectionModeResetsScanYoloValidationState() {
        let engine = CardDetectionEngine()
        let initial = engine.scanYOLOValidationStateSnapshot()

        engine.updateDetectionMode(.auto)

        let updated = engine.scanYOLOValidationStateSnapshot()
        XCTAssertEqual(updated.generation, initial.generation + 1)
        XCTAssertEqual(updated.boxes, [])
        XCTAssertNil(updated.lastTimestamp)
        XCTAssertFalse(updated.hasCachedBoxes)
    }

    func testUpdateIsLandscapeResetsScanYoloValidationState() {
        let engine = CardDetectionEngine()
        let initial = engine.scanYOLOValidationStateSnapshot()

        engine.updateIsLandscape(true)

        let updated = engine.scanYOLOValidationStateSnapshot()
        XCTAssertEqual(updated.generation, initial.generation + 1)
        XCTAssertEqual(updated.boxes, [])
        XCTAssertNil(updated.lastTimestamp)
        XCTAssertFalse(updated.hasCachedBoxes)
    }
}
