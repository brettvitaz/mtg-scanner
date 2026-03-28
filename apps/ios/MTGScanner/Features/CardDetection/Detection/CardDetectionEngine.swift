import AVFoundation
import CoreGraphics
import CoreML
import Vision

/// Processes live camera frames and detects MTG card-shaped rectangles.
///
/// Threading model:
/// - `processFrame(_:)` is called from the camera queue.
/// - Vision/CoreML requests execute synchronously on a dedicated serial Vision queue.
/// - Frame dropping: if a request is already in flight, incoming frames are discarded.
/// - Results are dispatched to the main queue via `onDetection`.
///
/// Detection paths:
/// - Table mode: VNCoreMLRequest using the trained YOLOv8n card detector model.
/// - Binder mode: VNDetectRectanglesRequest to find the page, then GridInterpolator
///   to subdivide into a 3×3 grid (no trained model needed for this path).
final class CardDetectionEngine {

    // MARK: - Properties

    var detectionMode: DetectionMode = .table

    /// Called on the main queue with the latest detected cards after each processed frame.
    var onDetection: (([DetectedCard]) -> Void)?

    private let visionQueue = DispatchQueue(label: "com.mtgscanner.vision", qos: .userInitiated)
    /// Guarded by visionQueue — never read/written from other queues.
    private var isProcessing = false
    /// Guarded by visionQueue — stabilizes detections with EMA smoothing + hysteresis.
    private let tracker = CardTracker()

    // MARK: - YOLO model (lazy — loaded once on first use on visionQueue)

    private var _coreMLRequest: VNCoreMLRequest?

    private func coreMLRequest() -> VNCoreMLRequest? {
        if let existing = _coreMLRequest { return existing }
        guard let modelURL = Bundle.main.url(forResource: "best", withExtension: "mlpackage"),
              let compiled = try? MLModel(contentsOf: modelURL,
                                          configuration: mlConfig()),
              let vnModel = try? VNCoreMLModel(for: compiled) else {
            return nil
        }
        let request = VNCoreMLRequest(model: vnModel)
        // .scaleFill avoids letterboxing — matches how YOLO was trained (padded square input)
        request.imageCropAndScaleOption = .scaleFill
        _coreMLRequest = request
        return request
    }

    private func mlConfig() -> MLModelConfiguration {
        let config = MLModelConfiguration()
        config.computeUnits = .all   // Neural Engine + GPU + CPU
        return config
    }

    // MARK: - Frame Processing

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let mode = detectionMode

        visionQueue.async { [weak self] in
            guard let self, !self.isProcessing else { return }
            self.isProcessing = true
            let raw = self.detect(in: pixelBuffer, timestamp: timestamp, mode: mode)
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
        mode: DetectionMode
    ) -> [DetectedCard] {
        switch mode {
        case .table:
            return detectWithYOLO(pixelBuffer: pixelBuffer, timestamp: timestamp)
        case .binder:
            return detectBinderGrid(in: pixelBuffer, timestamp: timestamp)
        }
    }

    // MARK: - YOLO Table Detection

    private func detectWithYOLO(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [DetectedCard] {
        guard let request = coreMLRequest() else {
            // Model failed to load — fall back to rectangle detection
            return detectWithRectangles(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }

        // The sensor delivers landscape pixel buffers (1920×1080).
        // .right tells Vision the image needs a 90° CCW rotation to appear upright.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .right,
                                            options: [:])
        try? handler.perform([request])

        // YOLOv8n exported with nms=False returns a raw MLMultiArray named "var_909"
        // via VNCoreMLFeatureValueObservation, not VNRecognizedObjectObservation.
        guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
              let output = observations.first(where: { $0.featureName == "var_909" })?.featureValue.multiArrayValue
                        ?? observations.first?.featureValue.multiArrayValue else {
            return []
        }

        return YOLODecoder().decode(output: output, timestamp: timestamp)
    }

    // MARK: - Binder Grid Detection (VNDetectRectanglesRequest)

    private func detectBinderGrid(in pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [DetectedCard] {
        let pageObservations = runRectangleRequest(
            pixelBuffer: pixelBuffer,
            maxObservations: 1,
            minAspectRatio: 0.60,
            maxAspectRatio: 0.95
        )

        guard let page = pageObservations.first else { return [] }

        let cells = GridInterpolator.subdivide(
            topLeft: page.topLeft,
            topRight: page.topRight,
            bottomRight: page.bottomRight,
            bottomLeft: page.bottomLeft,
            rows: 3,
            cols: 3
        )

        return cells.map { cell in
            let box = CGRect(
                x: min(cell.topLeft.x, cell.bottomLeft.x),
                y: min(cell.bottomLeft.y, cell.bottomRight.y),
                width: abs(cell.topRight.x - cell.topLeft.x),
                height: abs(cell.topLeft.y - cell.bottomLeft.y)
            )
            return DetectedCard(
                boundingBox: box,
                topLeft: cell.topLeft,
                topRight: cell.topRight,
                bottomRight: cell.bottomRight,
                bottomLeft: cell.bottomLeft,
                confidence: page.confidence,
                timestamp: timestamp
            )
        }
    }

    // MARK: - Rectangle Request (used for binder mode + fallback)

    private func detectWithRectangles(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [DetectedCard] {
        let observations = runRectangleRequest(
            pixelBuffer: pixelBuffer,
            maxObservations: 10,
            minAspectRatio: 0.1,
            maxAspectRatio: 1.0
        )
        return observations.map { DetectedCard(from: $0, timestamp: timestamp) }
    }

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
        request.minimumConfidence = 0.4
        request.minimumAspectRatio = minAspectRatio
        request.maximumAspectRatio = maxAspectRatio
        request.quadratureTolerance = 15.0

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .right,
                                            options: [:])
        try? handler.perform([request])
        return results
    }
}

// MARK: - DetectedCard convenience init from VNRectangleObservation

private extension DetectedCard {
    init(from obs: VNRectangleObservation, timestamp: TimeInterval) {
        self.init(
            boundingBox: obs.boundingBox,
            topLeft:     obs.topLeft,
            topRight:    obs.topRight,
            bottomRight: obs.bottomRight,
            bottomLeft:  obs.bottomLeft,
            confidence:  obs.confidence,
            timestamp:   timestamp
        )
    }
}
