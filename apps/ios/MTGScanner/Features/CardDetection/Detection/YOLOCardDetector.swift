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
        runDetection(handler: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]))
    }

    /// Detect cards in a CGImage (e.g., from a captured still photo).
    ///
    /// The image is passed in its natural orientation. Vision handles scaling internally.
    func detect(in cgImage: CGImage) -> [CardBoundingBox] {
        runDetection(handler: VNImageRequestHandler(cgImage: cgImage, options: [:]))
    }

    private func runDetection(handler: VNImageRequestHandler) -> [CardBoundingBox] {
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

        try? handler.perform([request])
        return result
    }

    // MARK: - Decoding

    /// Decode the raw YOLOv8 output tensor [1, 5, N] into bounding boxes.
    ///
    /// The 5 channels are [cx, cy, w, h, class_confidence] for the single 'card' class.
    /// Coordinates are normalized to [0,1] relative to the model input size.
    func decode(output: MLMultiArray) -> [CardBoundingBox] {
        Self.decode(output: output, confidenceThreshold: confidenceThreshold)
    }

    static func decode(output: MLMultiArray, confidenceThreshold: Float) -> [CardBoundingBox] {
        guard
            output.shape.count == 3,
            output.shape[0].intValue == 1,
            output.shape[1].intValue == 5
        else { return [] }

        let numAnchors = output.shape[2].intValue
        guard numAnchors > 0, output.strides.count == 3 else { return [] }

        let channelStride = output.strides[1].intValue
        let anchorStride = output.strides[2].intValue

        var candidates: [(rect: CGRect, confidence: Float)] = []
        candidates.reserveCapacity(64)

        if output.dataType == .float32 {
            decodeFloat32Candidates(
                into: &candidates,
                output: output,
                anchorCount: numAnchors,
                confidenceThreshold: confidenceThreshold,
                channelStride: channelStride,
                anchorStride: anchorStride
            )
        } else {
            decodeNSNumberCandidates(
                into: &candidates,
                output: output,
                anchorCount: numAnchors,
                confidenceThreshold: confidenceThreshold
            )
        }

        return nonMaxSuppression(candidates)
    }

    // MARK: - NMS

    /// Greedy non-maximum suppression: keeps the highest-confidence box and removes
    /// any lower-confidence box whose IoU with it exceeds `iouThreshold`.
    static func nonMaxSuppression(
        _ boxes: [(rect: CGRect, confidence: Float)],
        iouThreshold: Float = YOLOCardDetector.iouThreshold
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

private extension YOLOCardDetector {
    static func value(
        in pointer: UnsafePointer<Float32>,
        channel: Int,
        anchor: Int,
        channelStride: Int,
        anchorStride: Int
    ) -> Float32 {
        pointer[channel * channelStride + anchor * anchorStride]
    }

    static func scalar(
        from pointer: UnsafePointer<Float32>,
        channel: Int,
        anchor: Int,
        channelStride: Int,
        anchorStride: Int
    ) -> CGFloat {
        CGFloat(
            value(
                in: pointer,
                channel: channel,
                anchor: anchor,
                channelStride: channelStride,
                anchorStride: anchorStride
            )
        )
    }

    static func makeRect(
        centerX: CGFloat,
        centerY: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
    }

    static func rect(
        from pointer: UnsafePointer<Float32>,
        anchor: Int,
        channelStride: Int,
        anchorStride: Int
    ) -> CGRect {
        let centerX = scalar(
            from: pointer,
            channel: 0,
            anchor: anchor,
            channelStride: channelStride,
            anchorStride: anchorStride
        )
        let centerY = scalar(
            from: pointer,
            channel: 1,
            anchor: anchor,
            channelStride: channelStride,
            anchorStride: anchorStride
        )
        let width = scalar(
            from: pointer,
            channel: 2,
            anchor: anchor,
            channelStride: channelStride,
            anchorStride: anchorStride
        )
        let height = scalar(
            from: pointer,
            channel: 3,
            anchor: anchor,
            channelStride: channelStride,
            anchorStride: anchorStride
        )
        return makeRect(centerX: centerX, centerY: centerY, width: width, height: height)
    }

    static func decodeFloat32Candidates(
        into candidates: inout [(rect: CGRect, confidence: Float)],
        output: MLMultiArray,
        anchorCount: Int,
        confidenceThreshold: Float,
        channelStride: Int,
        anchorStride: Int
    ) {
        let pointer = output.dataPointer.assumingMemoryBound(to: Float32.self)

        for anchor in 0..<anchorCount {
            let confidence = value(
                in: pointer,
                channel: 4,
                anchor: anchor,
                channelStride: channelStride,
                anchorStride: anchorStride
            )
            guard confidence >= confidenceThreshold else { continue }
            let rect = rect(
                from: pointer,
                anchor: anchor,
                channelStride: channelStride,
                anchorStride: anchorStride
            )
            candidates.append((rect, confidence))
        }
    }

    static func decodeNSNumberCandidates(
        into candidates: inout [(rect: CGRect, confidence: Float)],
        output: MLMultiArray,
        anchorCount: Int,
        confidenceThreshold: Float
    ) {
        for anchor in 0..<anchorCount {
            let confidence = output[[0, 4, anchor] as [NSNumber]].floatValue
            guard confidence >= confidenceThreshold else { continue }
            let rect = makeRect(
                centerX: CGFloat(output[[0, 0, anchor] as [NSNumber]].floatValue),
                centerY: CGFloat(output[[0, 1, anchor] as [NSNumber]].floatValue),
                width: CGFloat(output[[0, 2, anchor] as [NSNumber]].floatValue),
                height: CGFloat(output[[0, 3, anchor] as [NSNumber]].floatValue)
            )
            candidates.append((rect, confidence))
        }
    }
}
