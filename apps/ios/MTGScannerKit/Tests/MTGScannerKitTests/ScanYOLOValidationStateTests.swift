import XCTest
@testable import MTGScannerKit

final class ScanYOLOValidationStateTests: XCTestCase {

    func testBoxesForFrameRequestsRefreshWhenCacheIsMissing() {
        var state = CardDetectionEngine.ScanYOLOValidationState()

        let decision = state.boxesForFrame(timestamp: 1.0)

        XCTAssertNil(decision.cachedBoxes)
        XCTAssertTrue(decision.shouldStartRefresh)
        XCTAssertTrue(state.refreshInFlight)
    }

    func testBoxesForFrameReturnsCachedBoxesWithoutRefreshWhileCacheIsFresh() {
        var state = CardDetectionEngine.ScanYOLOValidationState()
        let cachedBoxes = [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)]
        state.storeRefresh(boxes: cachedBoxes, timestamp: 1.0, generation: state.generation)

        let decision = state.boxesForFrame(timestamp: 1.1)

        XCTAssertEqual(decision.cachedBoxes, cachedBoxes)
        XCTAssertFalse(decision.shouldStartRefresh)
        XCTAssertFalse(state.refreshInFlight)
    }

    func testBoxesForFrameReturnsCachedBoxesWhileSchedulingAsyncRefreshWhenCacheIsStale() {
        var state = CardDetectionEngine.ScanYOLOValidationState()
        let cachedBoxes = [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)]
        state.storeRefresh(boxes: cachedBoxes, timestamp: 1.0, generation: state.generation)

        let decision = state.boxesForFrame(timestamp: 1.4)

        XCTAssertEqual(decision.cachedBoxes, cachedBoxes)
        XCTAssertTrue(decision.shouldStartRefresh)
        XCTAssertTrue(state.refreshInFlight)
    }

    func testBoxesForFrameDoesNotScheduleDuplicateRefreshWhileOneIsRunning() {
        var state = CardDetectionEngine.ScanYOLOValidationState()
        let cachedBoxes = [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)]
        state.storeRefresh(boxes: cachedBoxes, timestamp: 1.0, generation: state.generation)

        _ = state.boxesForFrame(timestamp: 1.4)
        let decision = state.boxesForFrame(timestamp: 1.41)

        XCTAssertEqual(decision.cachedBoxes, cachedBoxes)
        XCTAssertFalse(decision.shouldStartRefresh)
        XCTAssertTrue(state.refreshInFlight)
    }

    func testStoreRefreshUpdatesCacheAndClearsRefreshInFlight() {
        var state = CardDetectionEngine.ScanYOLOValidationState()
        _ = state.boxesForFrame(timestamp: 1.0)
        let refreshedBoxes = [CGRect(x: 0.2, y: 0.3, width: 0.25, height: 0.35)]

        state.storeRefresh(boxes: refreshedBoxes, timestamp: 1.2, generation: state.generation)

        XCTAssertEqual(state.boxes, refreshedBoxes)
        XCTAssertEqual(state.lastTimestamp ?? 0, 1.2, accuracy: 0.001)
        XCTAssertTrue(state.hasCachedBoxes)
        XCTAssertFalse(state.refreshInFlight)
    }

    func testResetClearsCacheAndBumpsGeneration() {
        var state = CardDetectionEngine.ScanYOLOValidationState()
        state.storeRefresh(
            boxes: [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)],
            timestamp: 1.0,
            generation: state.generation
        )

        let previousGeneration = state.generation
        state.reset()

        XCTAssertEqual(state.boxes, [])
        XCTAssertNil(state.lastTimestamp)
        XCTAssertFalse(state.hasCachedBoxes)
        XCTAssertFalse(state.refreshInFlight)
        XCTAssertEqual(state.frameCounter, 0)
        XCTAssertEqual(state.generation, previousGeneration + 1)
    }

    func testStoreRefreshIgnoresStaleGeneration() {
        var state = CardDetectionEngine.ScanYOLOValidationState()
        let initialGeneration = state.generation
        _ = state.boxesForFrame(timestamp: 1.0)
        state.reset()

        state.storeRefresh(
            boxes: [CGRect(x: 0.2, y: 0.3, width: 0.25, height: 0.35)],
            timestamp: 1.2,
            generation: initialGeneration
        )

        XCTAssertEqual(state.boxes, [])
        XCTAssertNil(state.lastTimestamp)
        XCTAssertFalse(state.hasCachedBoxes)
        XCTAssertFalse(state.refreshInFlight)
    }
}
