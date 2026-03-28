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
/// - Table mode: VNDetectRectanglesRequest filtered by RectangleFilter.
/// - Binder mode: VNDetectRectanglesRequest to find the page, then GridInterpolator
///   to subdivide into a 3×3 grid.
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
            return detectTableCards(pixelBuffer: pixelBuffer, timestamp: timestamp)
        case .binder:
            return detectBinderGrid(in: pixelBuffer, timestamp: timestamp)
        }
    }

    // MARK: - Rectangle Table Detection

    #if DEBUG
    private var _debugTableFrameCount = 0
    #endif

    private func detectTableCards(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [DetectedCard] {
        let observations = runRectangleRequest(
            pixelBuffer: pixelBuffer,
            maxObservations: 10,
            minAspectRatio: RectangleFilter.visionMinAspectRatio,
            maxAspectRatio: RectangleFilter.visionMaxAspectRatio
        )
        let filtered = RectangleFilter().filter(observations)

        #if DEBUG
        _debugTableFrameCount += 1
        if _debugTableFrameCount % 30 == 1 {
            print("[RectDetect] bounds=[\(RectangleFilter.visionMinAspectRatio), \(RectangleFilter.visionMaxAspectRatio)] raw=\(observations.count) filtered=\(filtered.count)")
            for (i, obs) in observations.enumerated() {
                let box = obs.boundingBox
                let topEdge = hypot(obs.topRight.x - obs.topLeft.x, obs.topRight.y - obs.topLeft.y)
                let bottomEdge = hypot(obs.bottomRight.x - obs.bottomLeft.x, obs.bottomRight.y - obs.bottomLeft.y)
                let leftEdge = hypot(obs.bottomLeft.x - obs.topLeft.x, obs.bottomLeft.y - obs.topLeft.y)
                let rightEdge = hypot(obs.bottomRight.x - obs.topRight.x, obs.bottomRight.y - obs.topRight.y)
                let d1 = hypot(obs.topRight.x - obs.bottomLeft.x, obs.topRight.y - obs.bottomLeft.y)
                let d2 = hypot(obs.topLeft.x - obs.bottomRight.x, obs.topLeft.y - obs.bottomRight.y)
                print("[RectDetect]   [\(i)] conf=\(String(format: "%.2f", obs.confidence)) box=\(String(format: "%.3f,%.3f %.3fx%.3f", box.minX, box.minY, box.width, box.height))")
                print("[RectDetect]     corners: tl=\(String(format: "%.3f,%.3f", obs.topLeft.x, obs.topLeft.y)) tr=\(String(format: "%.3f,%.3f", obs.topRight.x, obs.topRight.y)) br=\(String(format: "%.3f,%.3f", obs.bottomRight.x, obs.bottomRight.y)) bl=\(String(format: "%.3f,%.3f", obs.bottomLeft.x, obs.bottomLeft.y))")
                print("[RectDetect]     edges: top=\(String(format: "%.3f", topEdge)) bot=\(String(format: "%.3f", bottomEdge)) left=\(String(format: "%.3f", leftEdge)) right=\(String(format: "%.3f", rightEdge)) diag=\(String(format: "%.3f", d1)),\(String(format: "%.3f", d2))")
            }
        }
        #endif

        return filtered.map { DetectedCard(from: $0, timestamp: timestamp) }
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
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
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
