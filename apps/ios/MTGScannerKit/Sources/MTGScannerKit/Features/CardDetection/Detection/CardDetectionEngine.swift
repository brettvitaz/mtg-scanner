import AVFoundation
import CoreGraphics
import Vision

/// Processes live camera frames and detects MTG card-shaped rectangles.
///
/// Threading model:
/// - `processFrame(_:)` is called from the camera queue.
/// - Vision requests execute synchronously on a dedicated serial Vision queue.
/// - Frame dropping: if a request is already in flight, incoming frames are discarded.
/// - Results are dispatched to the main queue via `onDetection`.
///
/// Detection paths:
/// - Scan mode: VNDetectRectanglesRequest filtered by RectangleFilter and validated by YOLO.
/// - Auto mode: YOLO card detection for the scanning-station flow.
public final class CardDetectionEngine: @unchecked Sendable {

    // MARK: - Properties

    /// Guarded by `visionQueue`; read and written only through `syncOnVisionQueue`.
    private var detectionMode: DetectionMode = .scan

    /// Guarded by `visionQueue`; reset in the same critical section as scan validation state.
    private var isLandscape: Bool = false

    // Loaded lazily so start-up time is not impacted if Auto Scan is not used.
    private lazy var yoloDetector: YOLOCardDetector? = YOLOCardDetector()

    /// Called on the main queue with the latest detected cards after each processed frame.
    public var onDetection: (([DetectedCard]) -> Void)?

    private let visionQueue = DispatchQueue(label: "com.mtgscanner.vision", qos: .userInitiated)
    private let visionQueueKey = DispatchSpecificKey<Void>()
    private let yoloQueue = DispatchQueue(label: "com.mtgscanner.yolo", qos: .userInitiated)
    /// Guarded by visionQueue — never read/written from other queues.
    private var isProcessing = false
    /// Guarded by visionQueue — stabilizes detections with EMA smoothing + hysteresis.
    private let tracker = CardTracker()
    /// Guarded by visionQueue — caches throttled YOLO validation for scan mode.
    private var scanYOLOValidationState = ScanYOLOValidationState()

    #if DEBUG
    var debugScanFrameCount = 0
    #endif

    public init() {
        visionQueue.setSpecific(key: visionQueueKey, value: ())
    }

    // MARK: - Frame Processing

    public func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let sendablePixelBuffer = SendablePixelBuffer(buffer: pixelBuffer)

        visionQueue.async { [weak self] in
            guard let self, !self.isProcessing else { return }
            self.isProcessing = true
            let raw = self.detect(
                in: sendablePixelBuffer.buffer,
                timestamp: timestamp,
                mode: self.detectionMode,
                isLandscape: self.isLandscape
            )
            let cards = self.tracker.update(detections: raw)
            self.isProcessing = false
            DispatchQueue.main.async {
                self.onDetection?(cards)
            }
        }
    }

    public func updateDetectionMode(_ mode: DetectionMode) {
        syncOnVisionQueue {
            guard detectionMode != mode else { return }
            detectionMode = mode
            scanYOLOValidationState.reset()
        }
    }

    func updateIsLandscape(_ isLandscape: Bool) {
        syncOnVisionQueue {
            guard self.isLandscape != isLandscape else { return }
            self.isLandscape = isLandscape
            scanYOLOValidationState.reset()
        }
    }

    /// Current detection mode (scan or auto).
    var currentDetectionMode: DetectionMode {
        syncOnVisionQueue { detectionMode }
    }

    // MARK: - Private Detection

    private func detect(
        in pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        mode: DetectionMode,
        isLandscape: Bool
    ) -> [DetectedCard] {
        switch mode {
        case .scan:
            return detectScanCards(pixelBuffer: pixelBuffer, timestamp: timestamp, isLandscape: isLandscape)
        case .auto:
            return detectAutoScanCard(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    private func syncOnVisionQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: visionQueueKey) != nil {
            return work()
        }
        return visionQueue.sync(execute: work)
    }

    // MARK: - Rectangle Scan Detection

    private func detectScanCards(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        isLandscape: Bool
    ) -> [DetectedCard] {
        let observations = runRectangleRequest(
            pixelBuffer: pixelBuffer,
            maxObservations: 10,
            minAspectRatio: RectangleFilter.visionMinAspectRatio,
            maxAspectRatio: RectangleFilter.visionMaxAspectRatio
        )
        let filterResult = RectangleFilter().filterResult(observations, isLandscape: isLandscape)
        let filtered = filterResult.observations
        let validationResult = validateScanObservations(
            filtered,
            pixelBuffer: pixelBuffer,
            timestamp: timestamp
        )

        #if DEBUG
        logScanFrame(
            observations: observations,
            filterResult: filterResult,
            validationResult: validationResult
        )
        #endif

        return validationResult.observations.map { DetectedCard(from: $0, timestamp: timestamp) }
    }

    // MARK: - Auto Scan YOLO Detection

    /// Detects cards using the bundled YOLO model for Auto Scan mode.
    ///
    /// Converts YOLO top-left-origin boxes to Vision bottom-left-origin coordinates
    /// so the existing overlay renderer can draw them without modification.
    private func detectAutoScanCard(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval
    ) -> [DetectedCard] {
        guard let boxes = runYOLODetection(in: pixelBuffer) else { return [] }
        return boxes.map { box in
            // Flip Y: Vision uses bottom-left origin; YOLO uses top-left origin.
            let visionBox = CGRect(
                x: box.rect.minX,
                y: 1.0 - box.rect.maxY,
                width: box.rect.width,
                height: box.rect.height
            )
            return DetectedCard(
                boundingBox: visionBox,
                topLeft: CGPoint(x: visionBox.minX, y: visionBox.maxY),
                topRight: CGPoint(x: visionBox.maxX, y: visionBox.maxY),
                bottomRight: CGPoint(x: visionBox.maxX, y: visionBox.minY),
                bottomLeft: CGPoint(x: visionBox.minX, y: visionBox.minY),
                confidence: box.confidence,
                timestamp: timestamp
            )
        }
    }

    // MARK: - Rectangle Request

    private func runRectangleRequest(
        pixelBuffer: CVPixelBuffer,
        maxObservations: Int,
        minAspectRatio: Float,
        maxAspectRatio: Float
    ) -> [VNRectangleObservation] {
        var results: [VNRectangleObservation] = []

        let request = VNDetectRectanglesRequest { req, _ in
            results = (req.results as? [VNRectangleObservation]) ?? []
        }
        request.maximumObservations = maxObservations
        request.minimumConfidence = RectangleFilter.minConfidence
        request.minimumAspectRatio = minAspectRatio
        request.maximumAspectRatio = maxAspectRatio
        request.quadratureTolerance = 15.0

        // No orientation hint — pass native landscape buffer so Vision returns corners
        // in native sensor coordinates, matching layerPointConverted's expected input space.
        // Vision detects cards of any aspect ratio within the specified range regardless of
        // whether the card is portrait or landscape relative to the sensor, so no hint is needed
        // to support landscape device orientation.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
        return results
    }

}

// MARK: - YOLO validation helpers

private extension CardDetectionEngine {
    func validateScanObservations(
        _ observations: [VNRectangleObservation],
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval
    ) -> ScanYOLOValidationResult {
        guard !observations.isEmpty else {
            return ScanYOLOValidationResult(
                observations: [], yoloBoxes: [], yoloAcceptedCount: 0, yoloRejectedCount: 0, usedFallback: false
            )
        }
        let yoloBoxes = scanYOLOBoxes(pixelBuffer: pixelBuffer, timestamp: timestamp)
        let validation = ScanYOLOSupport.validate(observations, with: yoloBoxes)
        return ScanYOLOValidationResult(
            observations: validation.observations,
            yoloBoxes: yoloBoxes ?? [],
            yoloAcceptedCount: validation.yoloAcceptedCount,
            yoloRejectedCount: validation.yoloRejectedCount,
            usedFallback: validation.usedFallback
        )
    }

    func scanYOLOBoxes(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [CGRect]? {
        let decision = scanYOLOValidationState.boxesForFrame(timestamp: timestamp)
        if decision.shouldStartRefresh {
            refreshScanYOLOBoxes(pixelBuffer: pixelBuffer, timestamp: timestamp, generation: decision.generation)
        }
        return decision.cachedBoxes
    }

    func runYOLODetection(in pixelBuffer: CVPixelBuffer) -> [CardBoundingBox]? {
        guard let detector = yoloDetector else { return nil }
        return yoloQueue.sync { detector.detect(in: pixelBuffer) }
    }

    func refreshScanYOLOBoxes(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, generation: Int) {
        guard let detector = yoloDetector else {
            scanYOLOValidationState.finishRefreshWithoutResult()
            return
        }
        let sendableDetector = SendableYOLODetector(detector: detector)
        let sendablePixelBuffer = SendablePixelBuffer(buffer: pixelBuffer)
        yoloQueue.async { [weak self] in
            let boxes = sendableDetector.detector.detect(in: sendablePixelBuffer.buffer)
                .map { ScanYOLOSupport.visionBox(from: $0.rect) }
            self?.visionQueue.async { [weak self] in
                guard let self else { return }
                self.scanYOLOValidationState.storeRefresh(boxes: boxes, timestamp: timestamp, generation: generation)
            }
        }
    }
}

// MARK: - DetectedCard convenience init from VNRectangleObservation

private extension DetectedCard {
    init(from obs: VNRectangleObservation, timestamp: TimeInterval) {
        self.init(
            boundingBox: obs.boundingBox,
            topLeft: obs.topLeft,
            topRight: obs.topRight,
            bottomRight: obs.bottomRight,
            bottomLeft: obs.bottomLeft,
            confidence: obs.confidence,
            timestamp: timestamp
        )
    }
}

private struct SendablePixelBuffer: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

private struct SendableYOLODetector: @unchecked Sendable {
    let detector: YOLOCardDetector
}

// MARK: - Debug logging

#if DEBUG
extension CardDetectionEngine {
    func logScanFrame(
        observations: [VNRectangleObservation],
        filterResult: RectangleFilter.FilterResult,
        validationResult: ScanYOLOValidationResult
    ) {
        debugScanFrameCount += 1
        guard debugScanFrameCount % 30 == 1 else { return }
        let minAR = RectangleFilter.visionMinAspectRatio
        let maxAR = RectangleFilter.visionMaxAspectRatio
        let filtered = filterResult.observations
        print("[RectDetect] bounds=[\(minAR), \(maxAR)]"
              + " raw=\(observations.count)"
              + " filtered=\(filtered.count)"
              + " final=\(validationResult.observations.count)")
        if filterResult.containmentSuppressionCount > 0 {
            print("[RectDetect]   suppressed nested=\(filterResult.containmentSuppressionCount)")
        }
        if validationResult.usedFallback {
            print("[RectDetect]   YOLO validation unavailable; using rectangle-only fallback")
        } else if validationResult.yoloRejectedCount > 0 || validationResult.yoloAcceptedCount > 0 {
            print("[RectDetect]   YOLO accepted=\(validationResult.yoloAcceptedCount)"
                  + " rejected=\(validationResult.yoloRejectedCount)"
                  + " boxes=\(validationResult.yoloBoxes.count)")
        }
        for (i, obs) in observations.enumerated() {
            logObservation(obs, index: i)
        }
    }

    private func logObservation(_ obs: VNRectangleObservation, index i: Int) {
        let box = obs.boundingBox
        let topEdge = hypot(obs.topRight.x - obs.topLeft.x, obs.topRight.y - obs.topLeft.y)
        let bottomEdge = hypot(obs.bottomRight.x - obs.bottomLeft.x, obs.bottomRight.y - obs.bottomLeft.y)
        let leftEdge = hypot(obs.bottomLeft.x - obs.topLeft.x, obs.bottomLeft.y - obs.topLeft.y)
        let rightEdge = hypot(obs.bottomRight.x - obs.topRight.x, obs.bottomRight.y - obs.topRight.y)
        let d1 = hypot(obs.topRight.x - obs.bottomLeft.x, obs.topRight.y - obs.bottomLeft.y)
        let d2 = hypot(obs.topLeft.x - obs.bottomRight.x, obs.topLeft.y - obs.bottomRight.y)
        let confStr = String(format: "%.2f", obs.confidence)
        let boxStr = String(format: "%.3f,%.3f %.3fx%.3f", box.minX, box.minY, box.width, box.height)
        print("[RectDetect]   [\(i)] conf=\(confStr) box=\(boxStr)")
        let tlStr = String(format: "%.3f,%.3f", obs.topLeft.x, obs.topLeft.y)
        let trStr = String(format: "%.3f,%.3f", obs.topRight.x, obs.topRight.y)
        let brStr = String(format: "%.3f,%.3f", obs.bottomRight.x, obs.bottomRight.y)
        let blStr = String(format: "%.3f,%.3f", obs.bottomLeft.x, obs.bottomLeft.y)
        print("[RectDetect]     corners: tl=\(tlStr) tr=\(trStr) br=\(brStr) bl=\(blStr)")
        let edgeStrs = [topEdge, bottomEdge, leftEdge, rightEdge].map { String(format: "%.3f", $0) }
        let diagStr = String(format: "%.3f,%.3f", d1, d2)
        print("[RectDetect]     edges: top=\(edgeStrs[0]) bot=\(edgeStrs[1])"
              + " left=\(edgeStrs[2]) right=\(edgeStrs[3]) diag=\(diagStr)")
    }

    func scanYOLOValidationStateSnapshot() -> ScanYOLOValidationState {
        syncOnVisionQueue { scanYOLOValidationState }
    }

    func setScanYOLOValidationStateForTesting(_ state: ScanYOLOValidationState) {
        syncOnVisionQueue { scanYOLOValidationState = state }
    }

    func storeScanYOLORefreshForTesting(boxes: [CGRect], timestamp: TimeInterval, generation: Int) {
        syncOnVisionQueue {
            scanYOLOValidationState.storeRefresh(boxes: boxes, timestamp: timestamp, generation: generation)
        }
    }

    func validateScanObservationsForTesting(
        _ observations: [VNRectangleObservation],
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval
    ) -> ScanYOLOValidationResult {
        syncOnVisionQueue {
            validateScanObservations(observations, pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }
}
#endif
