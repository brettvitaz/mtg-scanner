import XCTest
import AVFoundation
@testable import MTGScanner

final class DetectionOverlayRendererTests: XCTestCase {

    // MARK: - Layer pool

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
        renderer.update(detections: cards, previewLayer: previewLayer, interfaceOrientation: .portrait)
        XCTAssertEqual(parent.sublayers?.count, 2)

        renderer.update(detections: [], previewLayer: previewLayer, interfaceOrientation: .portrait)
        // Layers remain in the pool but should all be hidden.
        let visible = parent.sublayers?.filter { !$0.isHidden } ?? []
        XCTAssertEqual(visible.count, 0)
    }

    func testUpdateAddsLayersToParentAsPoolGrows() {
        let parent = CALayer()
        let renderer = DetectionOverlayRenderer(detectionLayer: parent)
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())

        renderer.update(detections: [makeCard(id: 0)], previewLayer: previewLayer, interfaceOrientation: .portrait)
        XCTAssertEqual(parent.sublayers?.count, 1)

        renderer.update(
            detections: [makeCard(id: 0), makeCard(id: 1), makeCard(id: 2)],
            previewLayer: previewLayer,
            interfaceOrientation: .portrait
        )
        XCTAssertEqual(parent.sublayers?.count, 3)
    }

    func testUpdateDoesNotShrinkPoolWhenDetectionCountDecreases() {
        // Pool layers are reused — count should stay at the high-water mark.
        let parent = CALayer()
        let renderer = DetectionOverlayRenderer(detectionLayer: parent)
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())

        renderer.update(
            detections: (0..<5).map { makeCard(id: $0) },
            previewLayer: previewLayer,
            interfaceOrientation: .portrait
        )
        XCTAssertEqual(parent.sublayers?.count, 5)

        renderer.update(detections: [makeCard(id: 0)], previewLayer: previewLayer, interfaceOrientation: .portrait)
        // Still 5 layers in the pool; only 1 is visible.
        XCTAssertEqual(parent.sublayers?.count, 5)
        let visible = parent.sublayers?.filter { !$0.isHidden } ?? []
        XCTAssertEqual(visible.count, 1)
    }

    func testClearHidesAllPoolLayers() {
        let parent = CALayer()
        let renderer = DetectionOverlayRenderer(detectionLayer: parent)
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())

        renderer.update(
            detections: (0..<3).map { makeCard(id: $0) },
            previewLayer: previewLayer,
            interfaceOrientation: .portrait
        )
        let visibleBefore = parent.sublayers?.filter { !$0.isHidden }.count ?? 0
        XCTAssertEqual(visibleBefore, 3)

        renderer.clear()
        let visibleAfter = parent.sublayers?.filter { !$0.isHidden }.count ?? 0
        XCTAssertEqual(visibleAfter, 0)
    }

    func testNewLayerHasExpectedStyling() {
        let parent = CALayer()
        let renderer = DetectionOverlayRenderer(detectionLayer: parent)
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())

        renderer.update(detections: [makeCard(id: 0)], previewLayer: previewLayer, interfaceOrientation: .portrait)

        guard let shapeLayer = parent.sublayers?.first as? CAShapeLayer else {
            XCTFail("Expected a CAShapeLayer in pool")
            return
        }
        XCTAssertEqual(shapeLayer.lineWidth, 2.0, accuracy: 0.001)
        // Green stroke
        XCTAssertEqual(shapeLayer.strokeColor, UIColor.systemGreen.cgColor)
    }

    // MARK: - Orientation-aware coordinate transform

    func testCaptureDevicePointPortraitFlipsAxesAndY() {
        // Portrait (.right hint): captureDevice = (1-vy, 1-vx)
        let point = CGPoint(x: 0.3, y: 0.7)
        let result = DetectionOverlayRenderer.captureDevicePoint(point, orientation: .portrait)
        XCTAssertEqual(result.x, 1.0 - point.y, accuracy: 0.001)
        XCTAssertEqual(result.y, 1.0 - point.x, accuracy: 0.001)
    }

    func testCaptureDevicePointLandscapeRightYFlipOnly() {
        // LandscapeRight (.up hint): captureDevice = (vx, 1-vy)
        let point = CGPoint(x: 0.3, y: 0.7)
        let result = DetectionOverlayRenderer.captureDevicePoint(point, orientation: .landscapeRight)
        XCTAssertEqual(result.x, point.x, accuracy: 0.001)
        XCTAssertEqual(result.y, 1.0 - point.y, accuracy: 0.001)
    }

    func testCaptureDevicePointLandscapeLeftFlipsX() {
        // LandscapeLeft (.down hint): captureDevice = (1-vx, vy)
        let point = CGPoint(x: 0.3, y: 0.7)
        let result = DetectionOverlayRenderer.captureDevicePoint(point, orientation: .landscapeLeft)
        XCTAssertEqual(result.x, 1.0 - point.x, accuracy: 0.001)
        XCTAssertEqual(result.y, point.y, accuracy: 0.001)
    }

    func testCaptureDevicePointPortraitUpsideDownSwapsAxes() {
        // PortraitUpsideDown (.left hint): captureDevice = (vy, vx)
        let point = CGPoint(x: 0.3, y: 0.7)
        let result = DetectionOverlayRenderer.captureDevicePoint(point, orientation: .portraitUpsideDown)
        XCTAssertEqual(result.x, point.y, accuracy: 0.001)
        XCTAssertEqual(result.y, point.x, accuracy: 0.001)
    }

    func testCaptureDevicePointCenterMapsToCenter() {
        // The center point (0.5, 0.5) should remain (0.5, 0.5) for all orientations.
        let center = CGPoint(x: 0.5, y: 0.5)
        for orientation: UIInterfaceOrientation in [.portrait, .landscapeRight, .landscapeLeft, .portraitUpsideDown] {
            let result = DetectionOverlayRenderer.captureDevicePoint(center, orientation: orientation)
            XCTAssertEqual(result.x, 0.5, accuracy: 0.001, "Center x failed for \(orientation.rawValue)")
            XCTAssertEqual(result.y, 0.5, accuracy: 0.001, "Center y failed for \(orientation.rawValue)")
        }
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
