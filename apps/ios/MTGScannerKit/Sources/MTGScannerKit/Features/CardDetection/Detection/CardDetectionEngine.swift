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
final class CardDetectionEngine: @unchecked Sendable {

    // MARK: - Properties

    var detectionMode: DetectionMode = .scan

    /// Set to `true` when the device interface orientation is landscape.
    /// Written from the main thread; read on the camera queue in `processFrame` — same
    /// pattern as `detectionMode`. The worst-case race during rotation is one stale frame.
    var isLandscape: Bool = false

    // Loaded lazily so start-up time is not impacted if Auto Scan is not used.
    private lazy var yoloDetector: YOLOCardDetector? = YOLOCardDetector()

    /// Called on the main queue with the latest detected cards after each processed frame.
    var onDetection: (([DetectedCard]) -> Void)?

    private let visionQueue = DispatchQueue(label: "com.mtgscanner.vision", qos: .userInitiated)
    /// Guarded by visionQueue — never read/written from other queues.
    private var isProcessing = false
    /// Guarded by visionQueue — stabilizes detections with EMA smoothing + hysteresis.
    private let tracker = CardTracker()
    /// Guarded by visionQueue — caches throttled YOLO validation for scan mode.
    private var scanYOLOValidationState = ScanYOLOValidationState()

    // MARK: - Frame Processing

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let mode = detectionMode
        let landscape = isLandscape

        visionQueue.async { [weak self] in
            guard let self, !self.isProcessing else { return }
            self.isProcessing = true
            let raw = self.detect(in: pixelBuffer, timestamp: timestamp, mode: mode, isLandscape: landscape)
            let cards = self.tracker.update(detections: raw)
            self.isProcessing = false
            DispatchQueue.main.async {
                self.onDetection?(cards)
            }
        }
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

    // MARK: - Rectangle Scan Detection

    #if DEBUG
    private var _debugScanFrameCount = 0
    #endif

    // swiftlint:disable:next function_body_length
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
        _debugScanFrameCount += 1
        if _debugScanFrameCount % 30 == 1 {
            let minAR = RectangleFilter.visionMinAspectRatio
            let maxAR = RectangleFilter.visionMaxAspectRatio
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
                let box = obs.boundingBox
                let topEdge = hypot(obs.topRight.x - obs.topLeft.x, obs.topRight.y - obs.topLeft.y)
                let bottomEdge = hypot(obs.bottomRight.x - obs.bottomLeft.x, obs.bottomRight.y - obs.bottomLeft.y)
                let leftEdge = hypot(obs.bottomLeft.x - obs.topLeft.x, obs.bottomLeft.y - obs.topLeft.y)
                let rightEdge = hypot(obs.bottomRight.x - obs.topRight.x, obs.bottomRight.y - obs.topRight.y)
                let d1 = hypot(obs.topRight.x - obs.bottomLeft.x, obs.topRight.y - obs.bottomLeft.y)
                let d2 = hypot(obs.topLeft.x - obs.bottomRight.x, obs.topLeft.y - obs.bottomRight.y)
                let confStr = String(format: "%.2f", obs.confidence)
                let boxStr = String(
                    format: "%.3f,%.3f %.3fx%.3f",
                    box.minX, box.minY, box.width, box.height
                )
                print("[RectDetect]   [\(i)] conf=\(confStr)"
                      + " box=\(boxStr)")
                let tlStr = String(format: "%.3f,%.3f", obs.topLeft.x, obs.topLeft.y)
                let trStr = String(format: "%.3f,%.3f", obs.topRight.x, obs.topRight.y)
                let brStr = String(format: "%.3f,%.3f", obs.bottomRight.x, obs.bottomRight.y)
                let blStr = String(format: "%.3f,%.3f", obs.bottomLeft.x, obs.bottomLeft.y)
                print("[RectDetect]     corners:"
                      + " tl=\(tlStr) tr=\(trStr)"
                      + " br=\(brStr) bl=\(blStr)")
                let edgeStrs = [topEdge, bottomEdge, leftEdge, rightEdge]
                    .map { String(format: "%.3f", $0) }
                let diagStr = String(format: "%.3f,%.3f", d1, d2)
                print("[RectDetect]     edges:"
                      + " top=\(edgeStrs[0]) bot=\(edgeStrs[1])"
                      + " left=\(edgeStrs[2]) right=\(edgeStrs[3])"
                      + " diag=\(diagStr)")
            }
        }
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
        guard let boxes = yoloDetector?.detect(in: pixelBuffer) else { return [] }
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

    private func validateScanObservations(
        _ observations: [VNRectangleObservation],
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval
    ) -> ScanYOLOValidationResult {
        guard !observations.isEmpty else {
            return ScanYOLOValidationResult(
                observations: [],
                yoloBoxes: [],
                yoloAcceptedCount: 0,
                yoloRejectedCount: 0,
                usedFallback: false
            )
        }

        guard let yoloBoxes = scanYOLOBoxes(pixelBuffer: pixelBuffer, timestamp: timestamp) else {
            return ScanYOLOValidationResult(
                observations: observations,
                yoloBoxes: [],
                yoloAcceptedCount: 0,
                yoloRejectedCount: 0,
                usedFallback: true
            )
        }

        var accepted: [VNRectangleObservation] = []
        accepted.reserveCapacity(observations.count)

        for observation in observations {
            if ScanYOLOSupport.supports(rectangle: observation.boundingBox, with: yoloBoxes) {
                accepted.append(observation)
            }
        }

        return ScanYOLOValidationResult(
            observations: accepted,
            yoloBoxes: yoloBoxes,
            yoloAcceptedCount: accepted.count,
            yoloRejectedCount: observations.count - accepted.count,
            usedFallback: false
        )
    }

    private func scanYOLOBoxes(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval
    ) -> [CGRect]? {
        scanYOLOValidationState.frameCounter += 1

        let cacheIsFresh: Bool
        if let lastTimestamp = scanYOLOValidationState.lastTimestamp {
            cacheIsFresh = (timestamp - lastTimestamp) <= ScanYOLOValidationState.cacheTTL
        } else {
            cacheIsFresh = false
        }

        let shouldRefresh = !scanYOLOValidationState.hasCachedBoxes
            || !cacheIsFresh
            || scanYOLOValidationState.frameCounter % ScanYOLOValidationState.validationStride == 0

        if !shouldRefresh {
            return scanYOLOValidationState.boxes
        }

        guard let detector = yoloDetector else { return nil }
        let boxes = detector.detect(in: pixelBuffer).map { ScanYOLOSupport.visionBox(from: $0.rect) }
        scanYOLOValidationState.boxes = boxes
        scanYOLOValidationState.lastTimestamp = timestamp
        scanYOLOValidationState.hasCachedBoxes = true
        return boxes
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

private extension CardDetectionEngine {
    struct ScanYOLOValidationState {
        static let validationStride = 3
        static let cacheTTL: TimeInterval = 0.25

        var boxes: [CGRect] = []
        var lastTimestamp: TimeInterval?
        var frameCounter = 0
        var hasCachedBoxes = false
    }

    struct ScanYOLOValidationResult {
        let observations: [VNRectangleObservation]
        let yoloBoxes: [CGRect]
        let yoloAcceptedCount: Int
        let yoloRejectedCount: Int
        let usedFallback: Bool
    }
}

enum ScanYOLOSupport {
    static let iouThreshold: CGFloat = 0.35
    static let coverageThreshold: CGFloat = 0.60

    static func supports(rectangle: CGRect, with yoloBoxes: [CGRect]) -> Bool {
        yoloBoxes.contains { yoloBox in
            RectangleFilter.iou(rectangle, yoloBox) >= iouThreshold
                || coverage(of: yoloBox, by: rectangle) >= coverageThreshold
        }
    }

    static func visionBox(from yoloBox: CGRect) -> CGRect {
        CGRect(
            x: yoloBox.minX,
            y: 1.0 - yoloBox.maxY,
            width: yoloBox.width,
            height: yoloBox.height
        )
    }

    static func coverage(of rect: CGRect, by coveringRect: CGRect) -> CGFloat {
        let intersection = rect.intersection(coveringRect)
        guard !intersection.isNull else { return 0 }
        let rectArea = RectangleFilter.area(of: rect)
        guard rectArea > 0 else { return 0 }
        return RectangleFilter.area(of: intersection) / rectArea
    }
}
