import XCTest
import AVFoundation
@testable import MTGScannerKit

final class DetectionOverlayRendererTests: XCTestCase {

    // MARK: - Layer pool

    private var detectionLayerPoolCount: Int {
        1 // zone overlay layer
    }

    func testUpdateWithNoDetectionsClearsAllLayers() {
        let parent = CALayer()
        let renderer = DetectionOverlayRenderer(detectionLayer: parent)
        let session = AVCaptureSession()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)

        // First populate the pool with 2 layers, then clear it.
        let cards = [
            makeCard(id: 0),
            makeCard(id: 1)
        ]
        renderer.update(detections: cards, previewLayer: previewLayer)
        XCTAssertEqual(parent.sublayers?.count, 2 + detectionLayerPoolCount)

        renderer.update(detections: [], previewLayer: previewLayer)
        // Layers remain in the pool but should all be hidden (excluding zone overlay).
        let visible = parent.sublayers?.filter { !$0.isHidden && $0 !== parent.sublayers?.first } ?? []
        XCTAssertEqual(visible.count, 0)
    }

    func testUpdateAddsLayersToParentAsPoolGrows() {
        let parent = CALayer()
        let renderer = DetectionOverlayRenderer(detectionLayer: parent)
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())

        renderer.update(detections: [makeCard(id: 0)], previewLayer: previewLayer)
        XCTAssertEqual(parent.sublayers?.count, 1 + detectionLayerPoolCount)

        renderer.update(detections: [makeCard(id: 0), makeCard(id: 1), makeCard(id: 2)], previewLayer: previewLayer)
        XCTAssertEqual(parent.sublayers?.count, 3 + detectionLayerPoolCount)
    }

    func testUpdateDoesNotShrinkPoolWhenDetectionCountDecreases() {
        // Pool layers are reused — count should stay at the high-water mark.
        let parent = CALayer()
        let renderer = DetectionOverlayRenderer(detectionLayer: parent)
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())

        renderer.update(detections: (0..<5).map { makeCard(id: $0) }, previewLayer: previewLayer)
        XCTAssertEqual(parent.sublayers?.count, 5 + detectionLayerPoolCount)

        renderer.update(detections: [makeCard(id: 0)], previewLayer: previewLayer)
        // Still 5 layers in the pool + zone overlay; only 1 is visible (detection layers, not zone).
        XCTAssertEqual(parent.sublayers?.count, 5 + detectionLayerPoolCount)
        let visible = parent.sublayers?.filter { !$0.isHidden && $0 !== parent.sublayers?.first } ?? []
        XCTAssertEqual(visible.count, 1)
    }

    func testClearHidesAllPoolLayers() {
        let parent = CALayer()
        let renderer = DetectionOverlayRenderer(detectionLayer: parent)
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())

        renderer.update(detections: (0..<3).map { makeCard(id: $0) }, previewLayer: previewLayer)
        let visibleBefore = parent.sublayers?.filter { !$0.isHidden && $0 !== parent.sublayers?.first }.count ?? 0
        XCTAssertEqual(visibleBefore, 3)

        renderer.clear()
        let visibleAfter = parent.sublayers?.filter { !$0.isHidden && $0 !== parent.sublayers?.first }.count ?? 0
        XCTAssertEqual(visibleAfter, 0)
    }

    func testNewLayerHasExpectedStyling() {
        let parent = CALayer()
        let renderer = DetectionOverlayRenderer(detectionLayer: parent)
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())

        renderer.update(detections: [makeCard(id: 0)], previewLayer: previewLayer)

        // Detection layers are at the end; zone overlay is first
        guard let shapeLayer = parent.sublayers?.last as? CAShapeLayer else {
            XCTFail("Expected a CAShapeLayer in pool")
            return
        }
        XCTAssertEqual(shapeLayer.lineWidth, 2.0, accuracy: 0.001)
        // Green stroke
        XCTAssertEqual(shapeLayer.strokeColor, UIColor.systemGreen.cgColor)
    }

    // MARK: - Coordinate transform

    func testVisionPointToLayerYFlipOnlyForAllOrientations() {
        // visionPointToLayer applies a Y-flip and then delegates all orientation
        // handling (portrait, landscape) to layerPointConverted via videoRotationAngle.
        // We verify the capture-device point passed is always (vx, 1-vy).
        let point = CGPoint(x: 0.3, y: 0.7)
        // With a disconnected preview layer, layerPointConverted returns the input unchanged,
        // so the output equals the capture-device point we computed.
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())
        let result = DetectionOverlayRenderer.visionPointToLayer(point, previewLayer: previewLayer)
        XCTAssertEqual(result.x, point.x, accuracy: 0.001)
        XCTAssertEqual(result.y, 1.0 - point.y, accuracy: 0.001)
    }

    func testVisionPointToLayerCenterMapsToCenter() {
        let center = CGPoint(x: 0.5, y: 0.5)
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())
        let result = DetectionOverlayRenderer.visionPointToLayer(center, previewLayer: previewLayer)
        XCTAssertEqual(result.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.y, 0.5, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeCard(id: Int) -> DetectedCard {
        DetectedCard(
            id: UUID(),
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3),
            topLeft: CGPoint(x: 0.1, y: 0.4),
            topRight: CGPoint(x: 0.3, y: 0.4),
            bottomRight: CGPoint(x: 0.3, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1),
            confidence: 0.9,
            timestamp: TimeInterval(id)
        )
    }
}
