import CoreML
import Vision

/// Bounding box returned by the YOLO card detector.
///
/// Coordinates are normalized (0–1) with top-left origin, directly from the model output.
struct CardBoundingBox {
    let rect: CGRect
    let confidence: Float
}

/// On-device card detector backed by the bundled YOLOv8n Core ML model.
///
/// The model (`MTGCardDetector.mlmodelc`) was trained on the Roboflow Magic Card
/// Detection Dataset 2. It outputs raw detections (no built-in NMS), so this class
/// applies greedy NMS before returning results.
///
/// Threading: `detect(in:)` runs synchronously on the calling queue. Callers are
/// responsible for dispatching to a background queue.
final class YOLOCardDetector {

    // MARK: - Configuration

    /// Minimum per-class confidence for a detection to be kept.
    var confidenceThreshold: Float = 0.5

    // MARK: - Private

    private static let outputName = "var_909"
    private static let iouThreshold: Float = 0.45

    private let visionModel: VNCoreMLModel

    // MARK: - Init

    init?() {
        guard
            let modelURL = Bundle.main.url(forResource: "MTGCardDetector", withExtension: "mlmodelc"),
            let mlModel = try? MLModel(contentsOf: modelURL),
            let vnModel = try? VNCoreMLModel(for: mlModel)
        else { return nil }
        self.visionModel = vnModel
    }

    // MARK: - Detection

    /// Detect cards in a pixel buffer.
    ///
    /// Returns boxes in normalized top-left-origin image coordinates after NMS.
    /// Returns an empty array if the model fails or finds no cards above the threshold.
    func detect(in pixelBuffer: CVPixelBuffer) -> [CardBoundingBox] {
        var result: [CardBoundingBox] = []

        let request = VNCoreMLRequest(model: visionModel) { [weak self] req, _ in
            guard let self else { return }
            guard
                let observations = req.results as? [VNCoreMLFeatureValueObservation],
                let observation = observations.first(where: { $0.featureName == Self.outputName }),
                let output = observation.featureValue.multiArrayValue
            else { return }
            result = self.decode(output: output)
        }
        // scaleFill avoids letterboxing, keeping output coords in [0,1] for both axes.
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
        return result
    }

    // MARK: - Decoding

    /// Decode the raw YOLOv8 output tensor [1, 5, N] into bounding boxes.
    ///
    /// The 5 channels are [cx, cy, w, h, class_confidence] for the single 'card' class.
    /// Coordinates are normalized to [0,1] relative to the model input size.
    func decode(output: MLMultiArray) -> [CardBoundingBox] {
        guard output.shape.count == 3 else { return [] }
        let numAnchors = output.shape[2].intValue
        guard numAnchors > 0 else { return [] }

        var candidates: [(rect: CGRect, confidence: Float)] = []
        candidates.reserveCapacity(64)

        if output.dataType == .float32 {
            let ptr = output.dataPointer.assumingMemoryBound(to: Float32.self)
            for i in 0..<numAnchors {
                let conf = ptr[4 * numAnchors + i]
                guard conf >= confidenceThreshold else { continue }
                let cx = CGFloat(ptr[0 * numAnchors + i])
                let cy = CGFloat(ptr[1 * numAnchors + i])
                let w  = CGFloat(ptr[2 * numAnchors + i])
                let h  = CGFloat(ptr[3 * numAnchors + i])
                candidates.append((CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), conf))
            }
        } else {
            // Fallback path handles Float16 and other types via NSNumber coercion.
            for i in 0..<numAnchors {
                let conf = output[[0, 4, i] as [NSNumber]].floatValue
                guard conf >= confidenceThreshold else { continue }
                let cx = CGFloat(output[[0, 0, i] as [NSNumber]].floatValue)
                let cy = CGFloat(output[[0, 1, i] as [NSNumber]].floatValue)
                let w  = CGFloat(output[[0, 2, i] as [NSNumber]].floatValue)
                let h  = CGFloat(output[[0, 3, i] as [NSNumber]].floatValue)
                candidates.append((CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), conf))
            }
        }

        return Self.nonMaxSuppression(candidates)
    }

    // MARK: - NMS

    /// Greedy non-maximum suppression: keeps the highest-confidence box and removes
    /// any lower-confidence box whose IoU with it exceeds `iouThreshold`.
    static func nonMaxSuppression(
        _ boxes: [(rect: CGRect, confidence: Float)],
        iouThreshold: Float = 0.45
    ) -> [CardBoundingBox] {
        let sorted = boxes.sorted { $0.confidence > $1.confidence }
        var kept: [CardBoundingBox] = []
        var suppressed = IndexSet()

        for i in sorted.indices {
            guard !suppressed.contains(i) else { continue }
            kept.append(CardBoundingBox(rect: sorted[i].rect, confidence: sorted[i].confidence))
            for j in (i + 1)..<sorted.count where !suppressed.contains(j) {
                if iou(sorted[j].rect, sorted[i].rect) > iouThreshold {
                    suppressed.insert(j)
                }
            }
        }
        return kept
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = Float(intersection.width * intersection.height)
        let unionArea = Float(a.width * a.height + b.width * b.height) - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
