import XCTest
import CoreVideo
import Vision
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

    func testUpdateDetectionModeClearsCachedYOLOBoxesBeforeNextValidation() {
        let engine = CardDetectionEngine()
        var state = CardDetectionEngine.ScanYOLOValidationState()
        let cachedBoxes = [CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.30)]
        state.storeRefresh(boxes: cachedBoxes, timestamp: 1.0, generation: state.generation)
        engine.setScanYOLOValidationStateForTesting(state)

        engine.updateDetectionMode(.auto)
        let result = engine.validateScanObservationsForTesting(
            [makeObservation(box: cachedBoxes[0], confidence: 0.9)],
            pixelBuffer: makePixelBuffer(),
            timestamp: 1.1
        )

        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.yoloBoxes, [])
        XCTAssertEqual(engine.scanYOLOValidationStateSnapshot().boxes, [])
    }

    func testUpdateIsLandscapeClearsCachedYOLOBoxesBeforeNextValidation() {
        let engine = CardDetectionEngine()
        var state = CardDetectionEngine.ScanYOLOValidationState()
        let cachedBoxes = [CGRect(x: 0.12, y: 0.14, width: 0.18, height: 0.28)]
        state.storeRefresh(boxes: cachedBoxes, timestamp: 1.0, generation: state.generation)
        engine.setScanYOLOValidationStateForTesting(state)

        engine.updateIsLandscape(true)
        let result = engine.validateScanObservationsForTesting(
            [makeObservation(box: cachedBoxes[0], confidence: 0.9)],
            pixelBuffer: makePixelBuffer(),
            timestamp: 1.1
        )

        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.yoloBoxes, [])
        XCTAssertEqual(engine.scanYOLOValidationStateSnapshot().boxes, [])
    }

    func testStoreRefreshFromStaleGenerationIsIgnoredAfterModeChange() {
        let engine = CardDetectionEngine()
        let staleGeneration = engine.scanYOLOValidationStateSnapshot().generation

        engine.updateDetectionMode(.auto)
        engine.storeScanYOLORefreshForTesting(
            boxes: [CGRect(x: 0.15, y: 0.15, width: 0.22, height: 0.32)],
            timestamp: 1.2,
            generation: staleGeneration
        )

        let updated = engine.scanYOLOValidationStateSnapshot()
        XCTAssertEqual(updated.boxes, [])
        XCTAssertNil(updated.lastTimestamp)
        XCTAssertFalse(updated.hasCachedBoxes)
        XCTAssertEqual(updated.generation, staleGeneration + 1)
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

    private func makeObservation(box: CGRect, confidence: Float) -> VNRectangleObservation {
        let observation = VNRectangleObservation()
        observation.setValue(box, forKey: "boundingBox")
        observation.setValue(confidence, forKey: "confidence")
        observation.setValue(CGPoint(x: box.minX, y: box.maxY), forKey: "topLeft")
        observation.setValue(CGPoint(x: box.maxX, y: box.maxY), forKey: "topRight")
        observation.setValue(CGPoint(x: box.maxX, y: box.minY), forKey: "bottomRight")
        observation.setValue(CGPoint(x: box.minX, y: box.minY), forKey: "bottomLeft")
        return observation
    }
}
