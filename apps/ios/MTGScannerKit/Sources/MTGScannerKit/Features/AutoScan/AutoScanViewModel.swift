import AVFoundation
import Foundation
import SwiftData
import UIKit

/// State machine for the Auto Scan mode.
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
@Observable
final class AutoScanViewModel {

    // MARK: - State

    enum CaptureState {
        case watching
        case settling
        case capturing
    }

    private(set) var isActive = false
    private(set) var captureState: CaptureState = .watching
    private(set) var statusMessage = "Tap Start to begin."
    private(set) var lastCroppedImage: UIImage?
    private(set) var isCalibrated = false
    var detectionZone: DetectionZone? {
        didSet { presenceTracker.setZone(detectionZone) }
    }

    // MARK: - Child Objects

    let presenceTracker: CardPresenceTracker
    let recognitionQueue: RecognitionQueue
    let identifiedCardsViewModel: IdentifiedCardsViewModel

    // MARK: - Configuration

    var captureDelay: TimeInterval = 2.0

    // MARK: - Wiring (set by ScanView after init)

    weak var captureCoordinator: CameraCaptureCoordinator?
    var modelContext: ModelContext?
    var apiBaseURL: String = ""

    // MARK: - Private

    private var settleTask: Task<Void, Never>?
    private let cropImage: @Sendable (UIImage) async -> CardCropResult

    private struct CropResult {
        let image: UIImage?
        let boundingBox: CGRect?
        let sourceSize: CGSize?
    }

    /// Video dimensions from session preset .hd1920x1080
    private static let videoSize = CGSize(width: 1920, height: 1080)

    // MARK: - Init

    init(detectorProvider: @escaping () -> YOLOCardDetector? = YOLOCardDetector.init,
         burstConfiguration: MotionBurstConfiguration = .balanced) {
        presenceTracker = CardPresenceTracker(
            detectorProvider: detectorProvider,
            burstConfiguration: burstConfiguration
        )
        recognitionQueue = RecognitionQueue()
        identifiedCardsViewModel = IdentifiedCardsViewModel()
        let service = CardCropService()
        cropImage = { image in await service.detectAndCrop(image: image) }
        setupSignalHandler()
        setupRecognitionCallback()
    }

    /// Designated initialiser for testing — allows injecting a custom `RecognitionQueue` and crop function.
    init(
        detectorProvider: @escaping () -> YOLOCardDetector? = YOLOCardDetector.init,
        recognitionQueue: RecognitionQueue,
        identifiedCardsViewModel: IdentifiedCardsViewModel? = nil,
        cropImage: @escaping @Sendable (UIImage) async -> CardCropResult = {
            await CardCropService().detectAndCrop(image: $0)
        }
    ) {
        presenceTracker = CardPresenceTracker(detectorProvider: detectorProvider)
        self.recognitionQueue = recognitionQueue
        self.identifiedCardsViewModel = identifiedCardsViewModel ?? IdentifiedCardsViewModel()
        self.cropImage = cropImage
        setupSignalHandler()
        setupRecognitionCallback()
    }

    convenience init(detector: YOLOCardDetector?) {
        self.init(detectorProvider: { detector })
    }

    private func setupSignalHandler() {
        presenceTracker.onNewCardSignal = { [weak self] boundingBox in
            Task { @MainActor [weak self] in self?.handleNewCardSignal(boundingBox: boundingBox) }
        }
    }

    private func setupRecognitionCallback() {
        recognitionQueue.onCardIdentified = { [weak self] card in
            let identifiedCard = IdentifiedCard(from: card)
            self?.identifiedCardsViewModel.addCard(identifiedCard)
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
        identifiedCardsViewModel.clearAll()
        presenceTracker.resetZone()
        isCalibrated = false
    }

    func cancelRecognition() {
        recognitionQueue.cancelAll()
    }

    /// Resets the detection zone calibration, reverting to default (full frame) detection.
    func resetDetectionZone() {
        presenceTracker.resetZone()
        isCalibrated = false
    }

    /// Updates the motion burst detection configuration.
    func updateMotionBurstConfiguration(_ configuration: MotionBurstConfiguration) {
        presenceTracker.burstConfiguration = configuration
    }

    // MARK: - Standard Scan Enqueue

    /// Crops `image` off-main and enqueues the resulting crops (or the full image) for recognition.
    ///
    /// Called by scan mode after a manual capture. Runs Vision detection
    /// on a detached background task to avoid blocking the main actor.
    @MainActor
    func enqueueCapturedImage(_ payload: RecognitionImagePayload, cropEnabled: Bool) async {
        let image = payload.displayImage
        if cropEnabled {
            let detectCrops = cropImage
            let crops = await Task.detached(priority: .userInitiated) {
                await detectCrops(image)
            }.value
            if crops.crops.isEmpty {
                recognitionQueue.enqueue(
                    payload: payload, isCropped: false, apiBaseURL: apiBaseURL, modelContext: modelContext
                )
                return
            }

            for crop in crops.crops {
                guard let cropPayload = RecognitionImagePayload.generatedJPEG(from: crop) else { continue }
                recognitionQueue.enqueue(
                    payload: cropPayload, isCropped: true, apiBaseURL: apiBaseURL, modelContext: modelContext
                )
            }
        } else {
            recognitionQueue.enqueue(
                payload: payload, isCropped: false, apiBaseURL: apiBaseURL, modelContext: modelContext
            )
        }
    }

    @MainActor
    func enqueueCapturedImage(_ image: UIImage, cropEnabled: Bool) async {
        guard let payload = RecognitionImagePayload.generatedJPEG(from: image) else { return }
        await enqueueCapturedImage(payload, cropEnabled: cropEnabled)
    }

    // MARK: - Frame Forwarding

    /// Forward camera frames to the presence tracker while active.
    ///
    /// Frames are dropped during `.settling` and `.capturing` — there is no value in
    /// processing motion while a capture is imminent or in progress, and doing so
    /// wastes CPU and risks a spurious second trigger before `markCaptured` runs.
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isActive, captureState == .watching else { return }
        presenceTracker.processFrame(sampleBuffer)
    }

    // MARK: - State Machine

    private func handleNewCardSignal(boundingBox: CGRect?) {
        guard isActive, boundingBox != nil else { return }
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard let payload = await captureCoordinator?.capturePhoto() else {
            presenceTracker.recoverFromCaptureFailure()
            captureState = .watching
            statusMessage = "Capture failed — watching…"
            return
        }

        let result = await cropCapturedPayload(payload)
        lastCroppedImage = result.image
        if let box = result.boundingBox, let sourceSize = result.sourceSize, !isCalibrated {
            let calibratedZone = DetectionZone.calibrated(
                fromYOLO: box,
                sourceSize: sourceSize,
                videoSize: Self.videoSize
            )
            // Set zone on the tracker directly via presenceQueue so the
            // reference update from markCaptured runs BEFORE the zone change.
            presenceTracker.markCapturedAndSetZone(calibratedZone)
            detectionZone = calibratedZone
            isCalibrated = true
        } else {
            presenceTracker.markCaptured()
        }
        enqueueAfterCapture(payload: payload, cropped: result.image)
        captureState = .watching
        statusMessage = "Captured! Watching for next card…"
    }
}

// MARK: - Crop Helpers
private extension AutoScanViewModel {
    private func cropCapturedPayload(_ payload: RecognitionImagePayload) async -> CropResult {
        let uprightImage = AutoScanCropHelper.normalizedImage(payload.displayImage)
        guard let cgImage = uprightImage.cgImage else {
            return CropResult(image: nil, boundingBox: nil, sourceSize: nil)
        }
        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        guard let box = await presenceTracker.detectBestBox(in: cgImage) else {
            return CropResult(image: nil, boundingBox: nil, sourceSize: nil)
        }
        let cropped = AutoScanCropHelper.cropImage(uprightImage, toNormalizedRect: box)
        return CropResult(image: cropped, boundingBox: box, sourceSize: sourceSize)
    }

    func enqueueAfterCapture(payload: RecognitionImagePayload, cropped: UIImage?) {
        if let cropped,
           let cropPayload = RecognitionImagePayload.generatedJPEG(from: cropped) {
            recognitionQueue.enqueue(
                payload: cropPayload, isCropped: true, apiBaseURL: apiBaseURL, modelContext: modelContext
            )
        } else {
            recognitionQueue.enqueue(
                payload: payload, isCropped: false, apiBaseURL: apiBaseURL, modelContext: modelContext
            )
        }
    }
}
