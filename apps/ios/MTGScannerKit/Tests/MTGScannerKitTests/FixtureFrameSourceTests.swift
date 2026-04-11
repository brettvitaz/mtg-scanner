import XCTest
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
        var received = false
        let expectation = expectation(description: "frame received")

        source.onPixelBuffer = { _, _ in
            if !received {
                received = true
                expectation.fulfill()
            }
        }
        source.start()
        waitForExpectations(timeout: 2.0)
        source.stop()

        XCTAssertTrue(received, "FixtureFrameSource must emit at least one frame after start()")
    }

    func testFrameSourceStopsEmittingAfterStop() {
        let source = FixtureFrameSource(frameInterval: 0.05)
        var countAfterStop = 0
        source.start()
        source.stop()

        source.onPixelBuffer = { _, _ in countAfterStop += 1 }
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(countAfterStop, 0, "No frames should be emitted after stop()")
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
