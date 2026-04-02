import AVFoundation
import Foundation
import SwiftData
import UIKit

/// State machine for the Quick Scan mode.
///
/// Observes `CardPresenceTracker` for new-card signals, runs a configurable settle
/// timer to wait for the card to stop moving, triggers a still-photo capture, then
/// enqueues the image for asynchronous recognition via `RecognitionQueue`.
///
/// State transitions:
/// ```
/// watching  ──(new card signal)──► settling
/// settling  ──(timer fires)──────► capturing ──► watching
/// settling  ──(new signal)───────► (ignored — timer keeps running)
/// ```
@MainActor
final class QuickScanViewModel: ObservableObject {

    // MARK: - State

    enum CaptureState {
        case watching
        case settling
        case capturing
    }

    @Published private(set) var isActive = false
    @Published private(set) var captureState: CaptureState = .watching
    @Published private(set) var statusMessage = "Tap Start to begin."
    @Published private(set) var lastCroppedImage: UIImage?

    // MARK: - Child Objects

    let presenceTracker: CardPresenceTracker
    let recognitionQueue: RecognitionQueue

    // MARK: - Configuration

    var captureDelay: TimeInterval = 2.0

    // MARK: - Wiring (set by ScanView after init)

    weak var captureCoordinator: CameraCaptureCoordinator?
    var modelContext: ModelContext?
    var apiBaseURL: String = ""

    // MARK: - Private

    private var settleTask: Task<Void, Never>?

    // MARK: - Init

    init(detectorProvider: @escaping () -> YOLOCardDetector? = YOLOCardDetector.init) {
        presenceTracker = CardPresenceTracker(detectorProvider: detectorProvider)
        recognitionQueue = RecognitionQueue()
        setupSignalHandler()
    }

    /// Designated initialiser for testing — allows injecting a custom `RecognitionQueue`.
    init(detectorProvider: @escaping () -> YOLOCardDetector? = YOLOCardDetector.init,
         recognitionQueue: RecognitionQueue) {
        presenceTracker = CardPresenceTracker(detectorProvider: detectorProvider)
        self.recognitionQueue = recognitionQueue
        setupSignalHandler()
    }

    convenience init(detector: YOLOCardDetector?) {
        self.init(detectorProvider: { detector })
    }

    private func setupSignalHandler() {
        presenceTracker.onNewCardSignal = { [weak self] boundingBox in
            Task { @MainActor [weak self] in self?.handleNewCardSignal(boundingBox: boundingBox) }
        }
    }

    // MARK: - Controls

    func start() {
        isActive = true
        captureState = .watching
        statusMessage = "Watching for cards…"
    }

    func stop() {
        isActive = false
        settleTask?.cancel()
        settleTask = nil
        captureState = .watching
        statusMessage = "Tap Start to begin."
    }

    // MARK: - Frame Forwarding

    /// Forward camera frames to the presence tracker while active.
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isActive, captureState != .capturing else { return }
        presenceTracker.processFrame(sampleBuffer)
    }

    // MARK: - State Machine

    private func handleNewCardSignal(boundingBox: CGRect?) {
        guard isActive else { return }
        switch captureState {
        case .watching:
            startSettleTimer()
        case .settling, .capturing:
            // Timer is already running (settling) or capture is in progress — don't interrupt.
            break
        }
    }

    private func startSettleTimer() {
        captureState = .settling
        statusMessage = "Card detected — settling…"
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(captureDelay))
            guard !Task.isCancelled else { return }
            await triggerCapture()
        }
    }

    private func triggerCapture() async {
        captureState = .capturing
        statusMessage = "Capturing…"

        guard let image = await captureCoordinator?.capturePhoto() else {
            captureState = .watching
            statusMessage = "Capture failed — watching…"
            return
        }

        let uprightImage = YOLOCropHelper.normalizedImage(image)
        let cropped: UIImage?
        if let cgImage = uprightImage.cgImage,
           let box = await presenceTracker.detectBestBox(in: cgImage) {
            cropped = YOLOCropHelper.cropImage(uprightImage, toNormalizedRect: box)
        } else {
            cropped = nil
        }
        let enqueueImage = cropped ?? image
        let isCropped = cropped != nil

        if isCropped { lastCroppedImage = enqueueImage }
        presenceTracker.markCaptured()
        recognitionQueue.enqueue(
            image: enqueueImage, isCropped: isCropped, apiBaseURL: apiBaseURL, modelContext: modelContext
        )
        captureState = .watching
        statusMessage = "Captured! Watching for next card…"
    }
}
