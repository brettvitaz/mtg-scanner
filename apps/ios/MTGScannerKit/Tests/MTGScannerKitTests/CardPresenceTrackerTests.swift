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

    func testGlobalVibrationOfRealCardSceneDoesNotSignalAndNextPlacementStillWorks() async throws {
        try await verifyVibration(vertical: false)
    }

    func testVerticalVibrationDoesNotSignalAndNextPlacementStillWorks() async throws {
        try await verifyVibration(vertical: true)
    }

    private func verifyVibration(vertical: Bool) async throws {
        let tracker = CardPresenceTracker(detectorProvider: { nil }, detectCards: { _ in
            [CardBoundingBox(rect: CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), confidence: 0.9)]
        })
        tracker.resetSession(UUID())
        let url = try XCTUnwrap(Bundle.module.url(forResource: "IMG_1955", withExtension: "jpeg"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let noSignal = expectation(description: "Stand vibration is not a new card")
        noSignal.isInverted = true
        tracker.onNewCardSignal = { _, _ in noSignal.fulfill() }
        for offset in Array(repeating: 0, count: 8) + [4, -4, 3, -3, 2, -2, 1, -1] +
            Array(repeating: 0, count: 8) {
            tracker.processFrame(try translatedFrame(image, offset: vertical ? 0 : offset,
                                                      vertical: vertical ? offset : 0))
            await tracker.finishRearming()
        }
        await fulfillment(of: [noSignal], timeout: 0.1)
        let next = expectation(description: "A real replacement still signals")
        tracker.onNewCardSignal = { _, _ in next.fulfill() }
        for _ in 0..<8 { tracker.processFrame(try uniformFrame(255)); await tracker.finishRearming() }
        await fulfillment(of: [next], timeout: 1)
    }

    func testAlternatingSpatialPatternsCannotSettleJustBecauseTheirAverageDifferenceMatches() async throws {
        let tracker = CardPresenceTracker(detectorProvider: { nil }, detectCards: { _ in
            [CardBoundingBox(rect: CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), confidence: 0.9)]
        })
        tracker.resetSession(UUID())
        let noSignal = expectation(description: "Still-moving samples must not signal")
        noSignal.isInverted = true
        tracker.onNewCardSignal = { _, _ in noSignal.fulfill() }
        for _ in 0..<8 { tracker.processFrame(try uniformFrame(128)); await tracker.finishRearming() }
        for index in 0..<12 {
            tracker.processFrame(try patternedFrame(phase: index % 2))
            await tracker.finishRearming()
        }
        await fulfillment(of: [noSignal], timeout: 0.1)
        let arrived = expectation(description: "A stable card can settle after spatial motion")
        tracker.onNewCardSignal = { _, _ in arrived.fulfill() }
        for _ in 0..<8 { tracker.processFrame(try uniformFrame(255)); await tracker.finishRearming() }
        await fulfillment(of: [arrived], timeout: 1)
    }

    func testLargeIdenticalCardIsNotVetoedWhenItOccupiesPeripheralTiles() async throws {
        let tracker = CardPresenceTracker(detectorProvider: { nil }, detectCards: { _ in
            [CardBoundingBox(rect: CGRect(x: 0.19, y: 0.11, width: 0.62, height: 0.78), confidence: 0.9)]
        })
        tracker.resetSession(UUID())
        let url = try XCTUnwrap(Bundle.module.url(forResource: "IMG_1955", withExtension: "jpeg"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let arrived = expectation(description: "Insufficient independent background must preserve eligibility")
        arrived.assertForOverFulfill = true
        tracker.onNewCardSignal = { _, _ in arrived.fulfill() }
        for offset in Array(repeating: 0, count: 8) + [4, -4, 3, -3, 2, -2] + Array(repeating: 0, count: 8) {
            tracker.processFrame(try translatedFrame(image, offset: offset))
            await tracker.finishRearming()
        }
        await fulfillment(of: [arrived], timeout: 1)
    }

    func testLocalReplacementCanReturnToIdenticalAppearanceAndStillSignal() async throws {
        let tracker = CardPresenceTracker(detectorProvider: { nil }, detectCards: { _ in
            [CardBoundingBox(rect: CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), confidence: 0.9)]
        })
        tracker.resetSession(UUID())
        let url = try XCTUnwrap(Bundle.module.url(forResource: "IMG_1955", withExtension: "jpeg"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let arrived = expectation(description: "Local replacement mixed with shake still signals once")
        arrived.assertForOverFulfill = true
        tracker.onNewCardSignal = { _, _ in arrived.fulfill() }
        for _ in 0..<8 { tracker.processFrame(try translatedFrame(image, offset: 0)); await tracker.finishRearming() }
        for offset in [4, -4, 3, -3] {
            tracker.processFrame(try renderedFrame { context in
                context.draw(image, in: CGRect(x: offset, y: 0, width: 256, height: 192))
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(x: 80 + offset * 2, y: 48, width: 96, height: 96))
            })
            await tracker.finishRearming()
        }
        for _ in 0..<8 { tracker.processFrame(try translatedFrame(image, offset: 0)); await tracker.finishRearming() }
        await fulfillment(of: [arrived], timeout: 1)
    }

    private func uniformFrame(_ value: UInt8) throws -> CMSampleBuffer {
        try renderedFrame { context in
            context.setFillColor(UIColor(white: CGFloat(value) / 255, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 192))
        }
    }

    private func translatedFrame(_ image: CGImage, offset: Int, vertical: Int = 0) throws -> CMSampleBuffer {
        try renderedFrame { context in
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 192))
            context.draw(image, in: CGRect(x: offset, y: vertical, width: 256, height: 192))
        }
    }

    private func patternedFrame(phase: Int) throws -> CMSampleBuffer {
        try renderedFrame { context in
            for y in 0..<12 {
                for x in 0..<16 {
                    context.setFillColor((x + y + phase) % 2 == 0 ? UIColor.black.cgColor : UIColor.white.cgColor)
                    context.fill(CGRect(x: x * 16, y: y * 16, width: 16, height: 16))
                }
            }
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
