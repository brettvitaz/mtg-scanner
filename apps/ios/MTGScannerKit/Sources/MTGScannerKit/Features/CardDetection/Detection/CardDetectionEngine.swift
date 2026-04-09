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

    /// Guarded by `visionQueue`; read and written only through `syncOnVisionQueue`.
    private var detectionMode: DetectionMode = .scan

    /// Guarded by `visionQueue`; reset in the same critical section as scan validation state.
    private var isLandscape: Bool = false

    // Loaded lazily so start-up time is not impacted if Auto Scan is not used.
    private lazy var yoloDetector: YOLOCardDetector? = YOLOCardDetector()

    /// Called on the main queue with the latest detected cards after each processed frame.
    var onDetection: (([DetectedCard]) -> Void)?

    private let visionQueue = DispatchQueue(label: "com.mtgscanner.vision", qos: .userInitiated)
    private let visionQueueKey = DispatchSpecificKey<Void>()
    private let yoloQueue = DispatchQueue(label: "com.mtgscanner.yolo", qos: .userInitiated)
    /// Guarded by visionQueue — never read/written from other queues.
    private var isProcessing = false
    /// Guarded by visionQueue — stabilizes detections with EMA smoothing + hysteresis.
    private let tracker = CardTracker()
    /// Guarded by visionQueue — caches throttled YOLO validation for scan mode.
    private var scanYOLOValidationState = ScanYOLOValidationState()

    init() {
        visionQueue.setSpecific(key: visionQueueKey, value: ())
    }

    // MARK: - Frame Processing

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
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

    func updateDetectionMode(_ mode: DetectionMode) {
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

    private func scanYOLOBoxes(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval
    ) -> [CGRect]? {
        let decision = scanYOLOValidationState.boxesForFrame(timestamp: timestamp)
        if decision.shouldStartRefresh {
            refreshScanYOLOBoxes(
                pixelBuffer: pixelBuffer,
                timestamp: timestamp,
                generation: decision.generation
            )
        }
        return decision.cachedBoxes
    }

    private func runYOLODetection(in pixelBuffer: CVPixelBuffer) -> [CardBoundingBox]? {
        guard let detector = yoloDetector else { return nil }
        return yoloQueue.sync {
            detector.detect(in: pixelBuffer)
        }
    }

    private func refreshScanYOLOBoxes(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        generation: Int
    ) {
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
                self.scanYOLOValidationState.storeRefresh(
                    boxes: boxes,
                    timestamp: timestamp,
                    generation: generation
                )
            }
        }
    }

    #if DEBUG
    func scanYOLOValidationStateSnapshot() -> ScanYOLOValidationState {
        syncOnVisionQueue { scanYOLOValidationState }
    }

    func setScanYOLOValidationStateForTesting(_ state: ScanYOLOValidationState) {
        syncOnVisionQueue {
            scanYOLOValidationState = state
        }
    }

    func storeScanYOLORefreshForTesting(
        boxes: [CGRect],
        timestamp: TimeInterval,
        generation: Int
    ) {
        syncOnVisionQueue {
            scanYOLOValidationState.storeRefresh(
                boxes: boxes,
                timestamp: timestamp,
                generation: generation
            )
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
    #endif
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

extension CardDetectionEngine {
    struct ScanYOLOValidationState {
        static let validationStride = 3
        static let cacheTTL: TimeInterval = 0.25

        var boxes: [CGRect] = []
        var lastTimestamp: TimeInterval?
        var frameCounter = 0
        var hasCachedBoxes = false
        var refreshInFlight = false
        var generation = 0

        mutating func boxesForFrame(timestamp: TimeInterval) -> ScanYOLORefreshDecision {
            frameCounter += 1

            let cacheIsFresh: Bool
            if let lastTimestamp {
                cacheIsFresh = (timestamp - lastTimestamp) <= Self.cacheTTL
            } else {
                cacheIsFresh = false
            }

            let shouldRefresh = !hasCachedBoxes
                || !cacheIsFresh
                || frameCounter % Self.validationStride == 0
            let shouldStartRefresh = shouldRefresh && !refreshInFlight

            if shouldStartRefresh {
                refreshInFlight = true
            }

            return ScanYOLORefreshDecision(
                cachedBoxes: hasCachedBoxes ? boxes : nil,
                shouldStartRefresh: shouldStartRefresh,
                generation: generation
            )
        }

        mutating func storeRefresh(boxes: [CGRect], timestamp: TimeInterval, generation: Int) {
            guard generation == self.generation else { return }
            self.boxes = boxes
            lastTimestamp = timestamp
            hasCachedBoxes = true
            refreshInFlight = false
        }

        mutating func finishRefreshWithoutResult() {
            refreshInFlight = false
        }

        mutating func reset() {
            boxes = []
            lastTimestamp = nil
            frameCounter = 0
            hasCachedBoxes = false
            refreshInFlight = false
            generation += 1
        }
    }

    struct ScanYOLORefreshDecision {
        let cachedBoxes: [CGRect]?
        let shouldStartRefresh: Bool
        let generation: Int
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
    static let looseCoverageAreaRatioThreshold: CGFloat = 1.8

    static func validate(
        _ observations: [VNRectangleObservation],
        with yoloBoxes: [CGRect]?
    ) -> ValidationResult {
        guard !observations.isEmpty else {
            return ValidationResult(
                observations: [],
                yoloAcceptedCount: 0,
                yoloRejectedCount: 0,
                usedFallback: false
            )
        }

        guard let yoloBoxes else {
            return ValidationResult(
                observations: observations,
                yoloAcceptedCount: 0,
                yoloRejectedCount: 0,
                usedFallback: true
            )
        }

        guard !yoloBoxes.isEmpty else {
            return ValidationResult(
                observations: observations,
                yoloAcceptedCount: 0,
                yoloRejectedCount: 0,
                usedFallback: true
            )
        }

        let supportScores = observations.map { bestSupportScore(for: $0.boundingBox, in: yoloBoxes) }
        let directlyAcceptedCount = supportScores.filter { $0 >= coverageThreshold }.count
        let rejectedIDs = nestedRejectionIDs(
            observations: observations,
            supportScores: supportScores
        )
        let accepted = observations.filter { !rejectedIDs.contains(ObjectIdentifier($0)) }

        return ValidationResult(
            observations: accepted,
            yoloAcceptedCount: directlyAcceptedCount,
            yoloRejectedCount: rejectedIDs.count,
            usedFallback: false
        )
    }

    static func supports(rectangle: CGRect, with yoloBoxes: [CGRect]) -> Bool {
        yoloBoxes.contains { supports(rectangle: rectangle, with: $0) }
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

    private static func bestSupportScore(for rectangle: CGRect, in yoloBoxes: [CGRect]) -> CGFloat {
        yoloBoxes.reduce(0) { bestScore, yoloBox in
            max(bestScore, supportScore(rectangle: rectangle, with: yoloBox))
        }
    }

    private static func supportScore(rectangle: CGRect, with yoloBox: CGRect) -> CGFloat {
        let iou = RectangleFilter.iou(rectangle, yoloBox)
        let areaRatio = largerToSmallerAreaRatio(between: rectangle, and: yoloBox)
        let yoloCoveredByRectangle = coverage(of: yoloBox, by: rectangle)
        let rectangleCoveredByYOLO = coverage(of: rectangle, by: yoloBox)
        let enclosureCoverage = yoloCoveredByRectangle >= coverageThreshold
            && areaRatio <= looseCoverageAreaRatioThreshold
        let looseCoverage = rectangleCoveredByYOLO >= coverageThreshold
            && areaRatio <= looseCoverageAreaRatioThreshold
        return max(
            iou,
            enclosureCoverage ? yoloCoveredByRectangle : 0,
            looseCoverage ? rectangleCoveredByYOLO : 0
        )
    }

    private static func supports(rectangle: CGRect, with yoloBox: CGRect) -> Bool {
        supportScore(rectangle: rectangle, with: yoloBox) >= coverageThreshold
    }

    private static func nestedRejectionIDs(
        observations: [VNRectangleObservation],
        supportScores: [CGFloat]
    ) -> Set<ObjectIdentifier> {
        var rejectedIDs: Set<ObjectIdentifier> = []

        for (candidateIndex, candidate) in observations.enumerated() {
            let candidateBox = candidate.boundingBox
            let candidateArea = RectangleFilter.area(of: candidateBox)
            guard candidateArea > 0 else { continue }
            guard supportScores[candidateIndex] < coverageThreshold else { continue }

            let shouldReject = observations.enumerated().contains { index, supported in
                guard index != candidateIndex else { return false }

                let supportedBox = supported.boundingBox
                let supportedArea = RectangleFilter.area(of: supportedBox)
                guard supportedArea / candidateArea >= RectangleFilter.containmentAreaRatioThreshold else {
                    return false
                }
                guard supportScores[index] >= coverageThreshold else { return false }
                return RectangleFilter.containmentRatio(of: candidateBox, in: supportedBox) >=
                    RectangleFilter.containmentThreshold
            }

            if shouldReject {
                rejectedIDs.insert(ObjectIdentifier(candidate))
            }
        }

        return rejectedIDs
    }

    private static func largerToSmallerAreaRatio(between a: CGRect, and b: CGRect) -> CGFloat {
        let aArea = RectangleFilter.area(of: a)
        let bArea = RectangleFilter.area(of: b)
        guard aArea > 0, bArea > 0 else { return .infinity }
        return max(aArea, bArea) / min(aArea, bArea)
    }

    struct ValidationResult {
        let observations: [VNRectangleObservation]
        let yoloAcceptedCount: Int
        let yoloRejectedCount: Int
        let usedFallback: Bool
    }
}

private struct SendablePixelBuffer: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

private struct SendableYOLODetector: @unchecked Sendable {
    let detector: YOLOCardDetector
}
