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
        lastCroppedImage = nil
        statusMessage = "Tap Start to begin."
    }

    // MARK: - Standard Scan Enqueue

    /// Crops `image` off-main and enqueues the resulting crops (or the full image) for recognition.
    ///
    /// Called by table and binder scan modes after a manual capture. Runs Vision detection
    /// on a detached background task to avoid blocking the main actor.
    func enqueueCapturedImage(
        _ image: UIImage,
        cropEnabled: Bool,
        cropService: CardCropService = CardCropService()
    ) async {
        if cropEnabled {
            let crops = await Task.detached(priority: .userInitiated) {
                await cropService.detectAndCrop(image: image)
            }.value
            let pairs = crops.crops.isEmpty ? [(image, false)] : crops.crops.map { ($0, true) }
            for (img, cropped) in pairs {
                recognitionQueue.enqueue(
                    image: img, isCropped: cropped, apiBaseURL: apiBaseURL, modelContext: modelContext
                )
            }
        } else {
            recognitionQueue.enqueue(
                image: image, isCropped: false, apiBaseURL: apiBaseURL, modelContext: modelContext
            )
        }
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

        lastCroppedImage = cropped
        presenceTracker.markCaptured()
        recognitionQueue.enqueue(
            image: enqueueImage, isCropped: isCropped, apiBaseURL: apiBaseURL, modelContext: modelContext
        )
        captureState = .watching
        statusMessage = "Captured! Watching for next card…"
    }
}
