import AVFoundation
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class StationTrackerIntegrationTests: XCTestCase {
    func testRealTrackerRearmsBeforeCompletionAndNextDropCapturesExactlyOnce() async throws {
        let box = CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6)
        let tracker = CardPresenceTracker(detectorProvider: { nil }, detectCards: { _ in
            [CardBoundingBox(rect: box, confidence: 0.9)]
        })
        let queue = RecognitionQueue()
        queue.maxConcurrent = 0
        let gate = TrackerCropGate()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        var photos = 0
        let model = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue, presenceTracker: tracker,
            capturePhoto: { photos += 1; return .cameraCapture(image: image, data: Data([1])) },
            detectBox: { _ in box }, cropImage: { _, _ in await gate.run() }
        )
        model.captureDelay = 0
        var completions = 0
        var haptics = 0
        var speeches: [String] = []
        model.feedback.haptic = { haptics += 1 }
        model.feedback.announce = { [weak model] message, _ in
            guard let model else { XCTFail("Capture model was released before feedback"); return }
            speeches.append(message)
            XCTAssertTrue(message.contains("Ready for the next card"))
            XCTAssertTrue(model.canCaptureManually)
            completions += 1
        }
        try await assertPreparationIsNotReady(model, gate: gate, photos: { photos }, completions: { completions })
        try await burst(model, baseline: 255, card: 0)
        XCTAssertEqual(photos, 1)
        await gate.finish(image)
        try await wait { completions == 1 }
        XCTAssertEqual([haptics, speeches.count], [1, 1])
        try await burst(model, baseline: 255, card: 0)
        try await wait { await gate.waiting }
        XCTAssertEqual(photos, 2)
        await gate.finish(image)
        try await wait { completions == 2 }
        XCTAssertEqual(queue.pendingCount, 2)
        XCTAssertEqual([haptics, speeches.count], [2, 2])
        try await assertZoomPreservesWorkAndResetsBaseline(model, queue: queue, photos: { photos })
    }

    private func assertPreparationIsNotReady(
        _ model: AutoScanViewModel, gate: TrackerCropGate, photos: () -> Int, completions: () -> Int
    ) async throws {
        model.start()
        try await burst(model, baseline: 0, card: 255)
        try await wait { await gate.waiting }
        XCTAssertEqual(photos(), 1)
        XCTAssertEqual(completions(), 0)
        XCTAssertEqual(model.stationStatus, .capturing)
    }

    private func assertZoomPreservesWorkAndResetsBaseline(
        _ model: AutoScanViewModel, queue: RecognitionQueue, photos: () -> Int
    ) async throws {
        let thumbnail = try XCTUnwrap(model.lastCroppedImage)
        XCTAssertTrue(model.isCalibrated)
        XCTAssertTrue(model.prepareForZoomChange(from: 1, to: 2))
        XCTAssertTrue(model.lastCroppedImage === thumbnail)
        XCTAssertEqual(queue.pendingCount, 2)
        XCTAssertFalse(model.isCalibrated)
        model.start()
        // The changed framing becomes a baseline, never a new arrival.
        try await burst(model, baseline: 100, card: 100)
        XCTAssertEqual(photos(), 2)
        model.stop()
    }

    private func burst(_ model: AutoScanViewModel, baseline: UInt8, card: UInt8) async throws {
        for value in Array(repeating: baseline, count: 8) + Array(repeating: card, count: 4) {
            model.processFrame(try frame(value))
            await model.presenceTracker.finishRearming()
            await Task.yield()
        }
    }

    private func frame(_ value: UInt8) throws -> CMSampleBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                                          nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)), Int32(value),
               CVPixelBufferGetBytesPerRow(pixels) * 64)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                       imageBuffer: pixels, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(
                       allocator: kCFAllocatorDefault, imageBuffer: pixels,
                       formatDescription: try XCTUnwrap(format), sampleTiming: &timing,
                       sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }

    private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Tracker/capture did not reach expected state")
    }
}

private actor TrackerCropGate {
    private var continuation: CheckedContinuation<CardCropResult, Never>?
    var waiting: Bool { continuation != nil }
    func run() async -> CardCropResult { await withCheckedContinuation { continuation = $0 } }
    func finish(_ image: UIImage) {
        continuation?.resume(returning: CardCropResult(crops: [image], detectedCount: 1))
        continuation = nil
    }
}
