import XCTest
import CoreVideo
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

    func testValidateScanObservationsSkipsYOLOStateChangesWhenNoRectanglesRemain() {
        let engine = CardDetectionEngine()
        let initial = engine.scanYOLOValidationStateSnapshot()
        let pixelBuffer = makePixelBuffer()

        let result = engine.validateScanObservationsForTesting([], pixelBuffer: pixelBuffer, timestamp: 1.0)

        let updated = engine.scanYOLOValidationStateSnapshot()
        XCTAssertEqual(result.observations.count, 0)
        XCTAssertEqual(result.yoloBoxes, [])
        XCTAssertEqual(result.yoloAcceptedCount, 0)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(updated.frameCounter, initial.frameCounter)
        XCTAssertFalse(updated.refreshInFlight)
        XCTAssertEqual(updated.generation, initial.generation)
    }

    private func makePixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            8,
            8,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        // swiftlint:disable:next force_unwrapping
        return pixelBuffer!
    }
}
