import AVFoundation
import CoreGraphics
import Vision

/// Processes live camera frames and detects MTG card-shaped rectangles.
///
/// Threading model:
/// - `processFrame(_:)` is called from the camera queue.
/// - Vision requests execute synchronously on a dedicated serial Vision queue.
/// - Frame dropping: if a Vision request is already in flight, incoming frames are
///   discarded — the camera session will not back up.
/// - Results are dispatched to the main queue via `onDetection`.
final class CardDetectionEngine {

    // MARK: - Properties

    var detectionMode: DetectionMode = .table

    /// Called on the main queue with the latest detected cards after each processed frame.
    var onDetection: (([DetectedCard]) -> Void)?

    private let visionQueue = DispatchQueue(label: "com.mtgscanner.vision", qos: .userInitiated)
    private let rectangleFilter = RectangleFilter()
    /// Guarded by visionQueue — never read/written from other queues.
    private var isProcessing = false

    // MARK: - Frame Processing

    /// Submit a camera frame for card detection.
    ///
    /// Frames arriving while a prior request is still running are silently dropped;
    /// the caller must not assume every frame produces a detection callback.
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let mode = detectionMode

        // tryAsync: if the queue already has a pending item, drop this frame.
        visionQueue.async { [weak self] in
            guard let self, !self.isProcessing else { return }
            self.isProcessing = true
            let cards = self.detect(in: pixelBuffer, timestamp: timestamp, mode: mode)
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
            return detectCards(in: pixelBuffer, timestamp: timestamp)
        case .binder:
            return detectBinderGrid(in: pixelBuffer, timestamp: timestamp)
        }
    }

    private func detectCards(in pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [DetectedCard] {
        let observations = runRectangleRequest(
            pixelBuffer: pixelBuffer,
            maxObservations: 10,
            minAspectRatio: Float(RectangleFilter.targetAspectRatio * (1 - RectangleFilter.aspectRatioTolerance)),
            maxAspectRatio: Float(RectangleFilter.targetAspectRatio * (1 + RectangleFilter.aspectRatioTolerance))
        )
        return rectangleFilter.filter(observations).map { DetectedCard(from: $0, timestamp: timestamp) }
    }

    private func detectBinderGrid(in pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [DetectedCard] {
        // Pass 1: detect the binder page as a single large rectangle.
        let pageObservations = runRectangleRequest(
            pixelBuffer: pixelBuffer,
            maxObservations: 1,
            minAspectRatio: 0.60,
            maxAspectRatio: 0.95
        )

        guard let page = pageObservations.first else { return [] }

        // Pass 2: subdivide the page into a 3×3 grid using bilinear interpolation.
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

        // The sensor delivers landscape pixel buffers (1920×1080, right side up).
        // .right tells Vision the image needs a 90° CCW rotation to appear upright,
        // which matches the portrait camera preview shown to the user.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])

        return results
    }
}

// MARK: - DetectedCard convenience init

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
