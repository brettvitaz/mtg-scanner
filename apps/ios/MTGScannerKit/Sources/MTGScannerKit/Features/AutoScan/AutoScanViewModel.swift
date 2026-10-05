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

    var onCardIdentified: ((RecognizedCard) -> Void)?

    // MARK: - Configuration

    var captureDelay: TimeInterval = 2.0

    // MARK: - Wiring (set by ScanView after init)

    weak var captureCoordinator: CameraCaptureCoordinator?
    var modelContext: ModelContext?
    var apiBaseURL: String = ""
#if DEBUG
    var debugSaveRawCapturesToPhotoLibrary = false
    var rawCaptureSaver: RawCaptureSaving = RawCaptureDebugSaver()
#endif

    // MARK: - Private

    private(set) var scanSessionID = UUID()
    private var captureOperationID: UUID?
    var canCaptureManually: Bool { captureOperationID == nil }
    private var capturePhoto: (@MainActor () async -> RecognitionImagePayload?)?
    private(set) var captureFocusPoint: CGPoint?
    var captureFocusedPhoto: (@MainActor (CGPoint?) async -> CameraCaptureResult)?
    private var detectBox: (@Sendable (CGImage) async -> CGRect?)?
    private var settleTask: Task<Void, Never>?
    private let cropImage: @Sendable (UIImage, CardCropHint?) async -> CardCropResult

    private struct CropResult {
        let image: UIImage?
        let boundingBox: CGRect?
    }

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
        cropImage = { image, hint in await service.detectAndCrop(image: image, hint: hint) }
        setupSignalHandler()
        setupRecognitionCallback()
    }

    /// Designated initialiser for testing — allows injecting a custom `RecognitionQueue` and crop function.
    init(
        detectorProvider: @escaping () -> YOLOCardDetector? = YOLOCardDetector.init,
        recognitionQueue: RecognitionQueue,
        identifiedCardsViewModel: IdentifiedCardsViewModel? = nil,
        capturePhoto: (@MainActor () async -> RecognitionImagePayload?)? = nil,
        detectBox: (@Sendable (CGImage) async -> CGRect?)? = nil,
        cropImage: @escaping @Sendable (UIImage, CardCropHint?) async -> CardCropResult = {
            await CardCropService().detectAndCrop(image: $0, hint: $1)
        }
    ) {
        presenceTracker = CardPresenceTracker(detectorProvider: detectorProvider)
        self.recognitionQueue = recognitionQueue
        self.identifiedCardsViewModel = identifiedCardsViewModel ?? IdentifiedCardsViewModel()
        self.detectBox = detectBox
        self.capturePhoto = capturePhoto
        self.cropImage = cropImage
        setupSignalHandler()
        setupRecognitionCallback()
    }

    convenience init(detector: YOLOCardDetector?) {
        self.init(detectorProvider: { detector })
    }

    private func setupSignalHandler() {
        presenceTracker.onNewCardSignal = { [weak self] boundingBox, sessionID in
            Task { @MainActor [weak self] in
                self?.handleNewCardSignal(boundingBox: boundingBox, sessionID: sessionID)
            }
        }
    }

    private func setupRecognitionCallback() {
        recognitionQueue.onCardIdentified = { [weak self] card in
            let identifiedCard = IdentifiedCard(from: card)
            self?.identifiedCardsViewModel.addCard(identifiedCard)
            self?.onCardIdentified?(card)
        }
    }

    // MARK: - Controls

    func start() {
        guard !isActive else { return }
        resetSession()
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
        resetSession()
    }

    private func resetSession() {
        captureFocusPoint = nil
        scanSessionID = UUID()
        detectionZone = nil
        isCalibrated = false
        presenceTracker.resetSession(scanSessionID)
    }

    /// Captures immediately, including when automatic scanning is stopped.
    func captureManually() {
        guard canCaptureManually else { return }
        settleTask?.cancel()
        settleTask = nil
        let sessionID = scanSessionID
        let operationID = beginCapture()
        Task { [weak self] in
            await self?.performCapture(sessionID: sessionID, operationID: operationID)
        }
    }

    func cancelRecognition() {
        recognitionQueue.cancelAll()
    }

    /// Resets the detection zone calibration, reverting to default (full frame) detection.
    func resetDetectionZone() {
        presenceTracker.resetZone()
        detectionZone = nil
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
                await detectCrops(image, nil)
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

#if DEBUG
    @MainActor
    func saveRawCaptureIfEnabled(_ payload: RecognitionImagePayload) async {
        guard debugSaveRawCapturesToPhotoLibrary else { return }
        await rawCaptureSaver.saveRawCapture(payload)
    }
#endif

    // MARK: - Frame Forwarding

    /// Forward camera frames to the presence tracker while active.
    ///
    /// Frames are dropped during `.settling` and `.capturing` — there is no value in
    /// processing motion while a capture is imminent or in progress, and doing so
    /// wastes CPU and risks a spurious second trigger before `markCaptured` runs.
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isActive, captureState == .watching, canCaptureManually else { return }
        presenceTracker.processFrame(sampleBuffer)
    }

    // MARK: - State Machine

    private func handleNewCardSignal(boundingBox: CGRect?, sessionID: UUID) {
        guard isActive, sessionID == scanSessionID, boundingBox != nil, canCaptureManually else { return }
        switch captureState {
        case .watching:
            captureFocusPoint = CameraFocus.point(fromYOLOBox: boundingBox)
            if let captureFocusPoint { captureCoordinator?.focus(on: captureFocusPoint) }
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
        let sessionID = scanSessionID
        settleTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(captureDelay))
            guard !Task.isCancelled, isActive, sessionID == scanSessionID, canCaptureManually else { return }
            let operationID = beginCapture()
            await performCapture(sessionID: sessionID, operationID: operationID)
        }
    }

    private func beginCapture() -> UUID {
        let operationID = UUID()
        captureOperationID = operationID
        captureState = .capturing
        statusMessage = "Capturing…"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return operationID
    }

    private func performCapture(sessionID: UUID, operationID: UUID) async {
        defer {
            if captureOperationID == operationID { captureOperationID = nil }
        }
        guard sessionID == scanSessionID else { return }
        let result = await captureResult()
        guard sessionID == scanSessionID else { return }
        switch result {
        case .success(let payload):
            await processAutoCapturedPayload(payload, sessionID: sessionID)
        case .failure(let failure):
            if isActive { presenceTracker.markCaptured() }
            captureState = .watching
            statusMessage = failure.message
        }
    }

    private func captureResult() async -> CameraCaptureResult {
        if let captureFocusedPhoto { return await captureFocusedPhoto(captureFocusPoint) }
        if let capturePhoto {
            return await capturePhoto().map { .success($0) } ?? .failure(.unavailable)
        }
        return await captureCoordinator?.captureFocusedPhoto(focusPoint: captureFocusPoint) ?? .failure(.unavailable)
    }

    func processAutoCapturedPayload(_ payload: RecognitionImagePayload) async {
        await processAutoCapturedPayload(payload, sessionID: scanSessionID)
    }

    private func processAutoCapturedPayload(_ payload: RecognitionImagePayload, sessionID: UUID) async {
#if DEBUG
        await saveRawCaptureIfEnabled(payload)
#endif
        guard sessionID == scanSessionID else { return }
        let result = await cropCapturedPayload(payload)
        guard sessionID == scanSessionID else { return }
        lastCroppedImage = result.image
        if isActive { acknowledgeCapture(boundingBox: result.boundingBox) }
        enqueueAfterCapture(payload: payload, cropped: result.image)
        captureState = .watching
        statusMessage = isActive ? "Captured! Watching for next card…" : "Captured! Tap Start to begin auto scan."
    }

    private func acknowledgeCapture(boundingBox: CGRect?) {
        guard let box = boundingBox, !isCalibrated else {
            presenceTracker.markCaptured()
            return
        }
        let calibratedZone = DetectionZone.calibrated(fromYOLO: box)
        presenceTracker.markCapturedAndSetZone(calibratedZone)
        detectionZone = calibratedZone
        isCalibrated = true
    }
}

// MARK: - Crop Helpers
private extension AutoScanViewModel {
    private func cropCapturedPayload(_ payload: RecognitionImagePayload) async -> CropResult {
        let uprightImage = AutoScanCropHelper.normalizedImage(payload.displayImage)
        guard let cgImage = uprightImage.cgImage else {
            return CropResult(image: nil, boundingBox: nil)
        }
        let box = if let detectBox {
            await detectBox(cgImage)
        } else {
            await presenceTracker.detectBestBox(in: cgImage)
        }
        guard let box else {
            return CropResult(image: nil, boundingBox: nil)
        }
        let hint = CardCropHint(yoloBoxTopLeft: box, preferSingleCrop: true)
        let cropResult = await cropImage(uprightImage, hint)
        let cropped = cropResult.crops.first
        return CropResult(image: cropped, boundingBox: box)
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
