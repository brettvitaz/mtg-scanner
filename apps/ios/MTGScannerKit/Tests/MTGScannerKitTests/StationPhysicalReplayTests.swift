import AVFoundation
import XCTest
@testable import MTGScannerKit

/// Opt-in acceptance replay; the user-authorized camera recording stays local, outside the repository.
@MainActor
final class StationPhysicalReplayTests: XCTestCase {
    func testStationaryTraceDoesNotCaptureAcrossWarmupPhases() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("tmp/capture-noise-correction/station-trace2.mov")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Second local physical stand recording is not installed")
        }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        for frame in stride(from: 0, to: 240, by: 4) {
            let offset = Double(frame) / 30
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = CMTimeRange(start: CMTime(seconds: offset, preferredTimescale: 600),
                                          duration: CMTime(seconds: 10 - offset, preferredTimescale: 600))
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            reader.add(output)
            XCTAssertTrue(reader.startReading())
            let run = PhysicalReplayRun()
            while let sample = output.copyNextSampleBuffer() { await run.feed(sample) }
            XCTAssertEqual(reader.status, .completed)
            XCTAssertTrue(run.events.isEmpty, "Stationary warmup offset \(offset): \(run.events)")
        }
    }

    func testSecondRecordedTracePreservesThreeArrivals() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("tmp/capture-noise-correction/station-trace2.mov")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Second local physical stand recording is not installed")
        }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let run = PhysicalReplayRun()
        while let sample = output.copyNextSampleBuffer() { await run.feed(sample) }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(run.events.count, 3)
        for (event, bounds) in zip(run.events, [(10.0, 12.0), (12.0, 15.0), (15.0, 17.0)]) {
            XCTAssertGreaterThanOrEqual(event, bounds.0)
            XCTAssertLessThanOrEqual(event, bounds.1)
        }
        print("[SecondPhysicalReplay] arrival signals: \(run.events)")
    }

    func testRecordedStartTapAndThreeDropsWithoutAdditionalArrivalDelay() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("tmp/capture-trigger-recovery/station-trace.mov")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Local physical stand recording is not installed")
        }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let run = PhysicalReplayRun()
        while let sample = output.copyNextSampleBuffer() {
            await run.feed(sample)
        }
        await run.tracker.finishRearming()
        await Task.yield()
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(run.events.count, 3, "Start/tap must not capture; every real drop must capture exactly once")
        // Controlled original-detector replay:14.033,19.967,25.633s. Allow at most150ms extra.
        for (event, bounds) in zip(run.events, [(13.0, 14.183), (19.0, 20.117), (25.0, 25.783)]) {
            XCTAssertGreaterThanOrEqual(event, bounds.0)
            XCTAssertLessThanOrEqual(event, bounds.1)
        }
        print("[PhysicalReplay] arrival signals: \(run.events)")
    }
}

@MainActor
private final class PhysicalReplayRun {
    let tracker = CardPresenceTracker(detectorProvider: { nil }, detectCards: { _ in
        [CardBoundingBox(rect: CGRect(x: 0.45, y: 0.30, width: 0.30, height: 0.39), confidence: 0.9)]
    })
    var events: [TimeInterval] = []
    private var currentTime: TimeInterval = 0
    private var captureEnds: TimeInterval?
    private var firstTime: TimeInterval?

    init() {
        tracker.resetSession(UUID())
        tracker.onNewCardSignal = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                events.append(currentTime)
                captureEnds = currentTime + 1.2 // Measured photo/crop preparation; no simulated added cooldown.
            }
        }
    }

    func feed(_ sample: CMSampleBuffer) async {
        let timestamp = sample.presentationTimeStamp.seconds
        if firstTime == nil { firstTime = timestamp }
        currentTime = timestamp - (firstTime ?? timestamp)
        if let captureEnds, currentTime >= captureEnds {
            tracker.markCapturedAndSetZone(.calibrated(from: CGRect(x: 0.45, y: 0.31, width: 0.30, height: 0.39)))
            self.captureEnds = nil
        }
        tracker.processFrame(sample)
        await tracker.finishRearming()
        await Task.yield()
    }
}
