import AVFoundation
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class CardPresenceTrackerTests: XCTestCase {
    func testConfidenceThresholdIsForwarded() {
        let tracker = CardPresenceTracker(detector: nil)
        tracker.confidenceThreshold = 0.7
        XCTAssertEqual(tracker.confidenceThreshold, 0.7, accuracy: 0.001)
    }

    func testResetUncalibratedSessionClearsPendingCaptureAndUsesFreshBaseline() async throws {
        try await verifyRestart(zone: nil)
    }

    func testResetCalibratedSessionClearsZoneAndPendingCapture() async throws {
        let zone = DetectionZone.calibrated(from: CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6))
        try await verifyRestart(zone: zone)
    }

    func testNilDetectorDoesNotSignalAfterMotion() async throws {
        let tracker = CardPresenceTracker(detector: nil)
        tracker.resetSession(UUID())
        let noSignal = expectation(description: "No detection without a detector")
        noSignal.isInverted = true
        tracker.onNewCardSignal = { _, _ in noSignal.fulfill() }
        try await feedBurst(tracker, baseline: 0, card: 255)
        await fulfillment(of: [noSignal], timeout: 0.05)
    }

    func testLowLevelImageNoiseDoesNotPreventCardArrival() async throws {
        let tracker = CardPresenceTracker(detectorProvider: { nil }, detectCards: { _ in
            [CardBoundingBox(rect: CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), confidence: 0.9)]
        })
        tracker.resetSession(UUID())
        let arrived = expectation(description: "A stationary arrival with low image noise signals promptly")
        arrived.assertForOverFulfill = true
        tracker.onNewCardSignal = { _, _ in arrived.fulfill() }
        for _ in 0..<8 {
            tracker.processFrame(try uniformFrame(0))
            await tracker.finishRearming()
        }
        // The card has stopped; only a +/-1 luminance fluctuation remains.
        // Its mean/reference difference is unchanged, and adjacent noise is below motionThreshold.
        for phase in 0..<4 {
            tracker.processFrame(try noisyFrame(180, phase: phase))
            await tracker.finishRearming()
        }
        await fulfillment(of: [arrived], timeout: 0.2)
    }

    func testNoisyRestingCardDoesNotRecaptureAndNextDropSignals() async throws {
        let tracker = CardPresenceTracker(detectorProvider: { nil }, detectCards: { _ in
            [CardBoundingBox(rect: CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), confidence: 0.9)]
        })
        tracker.resetSession(UUID())
        for _ in 0..<8 {
            tracker.processFrame(try uniformFrame(0))
            await tracker.finishRearming()
        }
        let first = expectation(description: "First arrival")
        first.assertForOverFulfill = true
        tracker.onNewCardSignal = { _, _ in first.fulfill() }
        for phase in 0..<4 {
            tracker.processFrame(try noisyFrame(180, phase: phase))
            await tracker.finishRearming()
        }
        await fulfillment(of: [first], timeout: 0.2)
        tracker.markCaptured()
        let duplicate = expectation(description: "Resting noise is not another card")
        duplicate.isInverted = true
        tracker.onNewCardSignal = { _, _ in duplicate.fulfill() }
        for phase in 0..<30 {
            tracker.processFrame(try noisyFrame(180, phase: phase))
            await tracker.finishRearming()
        }
        await fulfillment(of: [duplicate], timeout: 0.1)
        let next = expectation(description: "Second arrival")
        next.assertForOverFulfill = true
        tracker.onNewCardSignal = { _, _ in next.fulfill() }
        for phase in 0..<4 {
            tracker.processFrame(try noisyFrame(80, phase: phase))
            await tracker.finishRearming()
        }
        await fulfillment(of: [next], timeout: 0.2)
    }

    private func noisyFrame(_ mean: Double, phase: Int) throws -> CMSampleBuffer {
        try renderedFrame { context in
            for y in 0..<12 {
                for x in 0..<16 {
                    let value = mean + ((x + y + phase) % 2 == 0 ? -1 : 1)
                    context.setFillColor(UIColor(white: value / 255, alpha: 1).cgColor)
                    context.fill(CGRect(x: x * 16, y: y * 16, width: 16, height: 16))
                }
            }
        }
    }

    func testIdenticalCopyArrivalCanReturnToTheSameAppearance() async throws {
        let tracker = CardPresenceTracker(detectorProvider: { nil }, detectCards: { _ in
            [CardBoundingBox(rect: CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), confidence: 0.9)]
        })
        tracker.resetSession(UUID())
        for _ in 0..<8 { tracker.processFrame(try uniformFrame(128)); await tracker.finishRearming() }
        let arrived = expectation(description: "Local passage is an arrival even with identical final appearance")
        arrived.assertForOverFulfill = true
        tracker.onNewCardSignal = { _, _ in arrived.fulfill() }
        for value: UInt8 in [0, 0, 128, 128, 128, 128] {
            tracker.processFrame(try uniformFrame(value))
            await tracker.finishRearming()
        }
        await fulfillment(of: [arrived], timeout: 0.2)
    }

    private func uniformFrame(_ value: UInt8) throws -> CMSampleBuffer {
        try renderedFrame { context in
            context.setFillColor(UIColor(white: CGFloat(value) / 255, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 192))
        }
    }

    private func renderedFrame(_ draw: (CGContext) -> Void) throws -> CMSampleBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 256, 192, kCVPixelFormatType_32BGRA,
                                          nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let context = try XCTUnwrap(CGContext(
            data: CVPixelBufferGetBaseAddress(pixels), width: 256, height: 192, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ))
        draw(context)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return try sampleBuffer(pixels)
    }

    private func verifyRestart(zone: DetectionZone?) async throws {
        let tracker = CardPresenceTracker(detectorProvider: { nil }, detectCards: { _ in
            [CardBoundingBox(rect: CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), confidence: 0.9)]
        })
        let firstSession = UUID()
        tracker.resetSession(firstSession)
        tracker.setZone(zone)
        let first = expectation(description: "First card signals")
        tracker.onNewCardSignal = { _, session in
            XCTAssertEqual(session, firstSession)
            first.fulfill()
        }
        try await feedBurst(tracker, baseline: 0, card: 255)
        await fulfillment(of: [first], timeout: 1)
        // No capture acknowledgement: this recreates Stop while settling.
        let newSession = UUID()
        tracker.resetSession(newSession)
        let restarted = expectation(description: "New session signals after fresh movement")
        tracker.onNewCardSignal = { _, session in
            XCTAssertEqual(session, newSession)
            restarted.fulfill()
        }
        try await feedBurst(tracker, baseline: 255, card: 0)
        await fulfillment(of: [restarted], timeout: 1)
        XCTAssertNil(tracker.detectionZone)
    }

    private func feedBurst(_ tracker: CardPresenceTracker, baseline: UInt8, card: UInt8) async throws {
        for value in Array(repeating: baseline, count: 8) + Array(repeating: card, count: 4) {
            tracker.processFrame(try makeFrame(value))
            // Still detection shares the queue, so this is a barrier for each frame.
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
            _ = await tracker.detectBestBox(in: try XCTUnwrap(image.cgImage))
        }
    }

    private func makeFrame(_ value: UInt8) throws -> CMSampleBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer
        ), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(pixels, []), kCVReturnSuccess)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
        memset(base, Int32(value), CVPixelBufferGetBytesPerRow(pixels) * 64)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return try sampleBuffer(pixels)
    }

    private func sampleBuffer(_ pixels: CVPixelBuffer) throws -> CMSampleBuffer {
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &format
        ), noErr)
        var timing = CMSampleTimingInfo(
            duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescription: try XCTUnwrap(format),
            sampleTiming: &timing, sampleBufferOut: &sample
        ), noErr)
        return try XCTUnwrap(sample)
    }
}
