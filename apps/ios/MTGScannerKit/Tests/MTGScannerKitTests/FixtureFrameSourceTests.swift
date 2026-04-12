import XCTest
@testable import MTGScannerFixtures
@testable import MTGScannerKit

@MainActor
final class FixtureFrameSourceTests: XCTestCase {

    // MARK: - Pixel buffer factory

    func testPixelBufferMatchesTargetSize() {
        let image = makeTestImage(size: CGSize(width: 100, height: 100))
        let target = FixtureFrameSource.targetSize

        guard let buffer = FixtureFrameSource.pixelBuffer(from: image, size: target) else {
            XCTFail("pixelBuffer(from:size:) must return a non-nil buffer")
            return
        }

        XCTAssertEqual(CVPixelBufferGetWidth(buffer), Int(target.width))
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), Int(target.height))
    }

    func testPixelBufferPixelFormatIsBGRA() {
        let image = makeTestImage(size: CGSize(width: 100, height: 100))

        guard let buffer = FixtureFrameSource.pixelBuffer(
            from: image,
            size: FixtureFrameSource.targetSize
        ) else {
            XCTFail("pixelBuffer(from:size:) must return a non-nil buffer")
            return
        }

        XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer), kCVPixelFormatType_32BGRA)
    }

    // MARK: - Frame emission

    func testFrameSourceEmitsAtLeastOneFrame() {
        let source = FixtureFrameSource(frameInterval: 0.05)
        let frameReceived = expectation(description: "frame received")
        frameReceived.assertForOverFulfill = false

        source.onPixelBuffer = { _, _ in frameReceived.fulfill() }
        source.start()
        waitForExpectations(timeout: 2.0)
        source.stop()
    }

    func testFrameSourceStopsEmittingAfterStop() {
        let source = FixtureFrameSource(frameInterval: 0.05)
        source.start()
        source.stop()

        let noFrames = expectation(description: "no frames after stop")
        noFrames.isInverted = true
        source.onPixelBuffer = { _, _ in noFrames.fulfill() }

        waitForExpectations(timeout: 0.3)
    }

    // MARK: - FixtureCameraViewController coordinate mapping

    func testImageRectCentersImageInSquareBounds() {
        // A 1920×1080 image inside a 200×200 square — height-constrained, width centered.
        let vc = FixtureCameraViewController()
        let rect = vc.imageBoundsForTesting(
            imageSize: CGSize(width: 1920, height: 1080),
            in: CGRect(origin: .zero, size: CGSize(width: 200, height: 200))
        )
        // scale = 200/1920 ≈ 0.1042; h = 1080 * scale ≈ 112.5
        let expectedScale = 200.0 / 1920.0
        XCTAssertEqual(rect.width, 1920 * expectedScale, accuracy: 0.01)
        XCTAssertEqual(rect.height, 1080 * expectedScale, accuracy: 0.01)
        // x should be 0 (width == bounds.width), y should be centered
        XCTAssertEqual(rect.minX, 0, accuracy: 0.01)
        XCTAssertGreaterThan(rect.minY, 0)
    }

    func testVisionPointCenter() {
        // Vision (0.5, 0.5) should map to the center of the image bounds.
        let vc = FixtureCameraViewController()
        let bounds = CGRect(x: 10, y: 20, width: 100, height: 80)
        let pt = vc.visionPointForTesting(CGPoint(x: 0.5, y: 0.5), in: bounds)
        XCTAssertEqual(pt.x, 60, accuracy: 0.01)
        XCTAssertEqual(pt.y, 60, accuracy: 0.01)
    }

    func testVisionPointTopLeft() {
        // Vision (0, 1) is top-left (Y-flipped: 1 - 1.0 = 0).
        let vc = FixtureCameraViewController()
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        let pt = vc.visionPointForTesting(CGPoint(x: 0, y: 1.0), in: bounds)
        XCTAssertEqual(pt.x, 0, accuracy: 0.01)
        XCTAssertEqual(pt.y, 0, accuracy: 0.01)
    }

    func testVisionPointBottomRight() {
        // Vision (1, 0) is bottom-right (Y-flipped: 1 - 0 = 1).
        let vc = FixtureCameraViewController()
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        let pt = vc.visionPointForTesting(CGPoint(x: 1.0, y: 0), in: bounds)
        XCTAssertEqual(pt.x, 100, accuracy: 0.01)
        XCTAssertEqual(pt.y, 80, accuracy: 0.01)
    }

    // MARK: - FixtureCameraViewController sample buffer factory

    func testMakeSampleBufferReturnsNonNilForValidPixelBuffer() {
        let image = makeTestImage(size: CGSize(width: 100, height: 100))
        guard let pixelBuffer = FixtureFrameSource.pixelBuffer(
            from: image,
            size: CGSize(width: 100, height: 100)
        ) else {
            XCTFail("Pixel buffer creation failed")
            return
        }

        let sampleBuffer = FixtureCameraViewController.makeSampleBuffer(from: pixelBuffer)
        XCTAssertNotNil(sampleBuffer, "makeSampleBuffer must return a valid CMSampleBuffer")
    }

    // MARK: - Helpers

    private func makeTestImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
