import CoreGraphics
import CoreML
import Vision

/// Decodes raw YOLOv8n Core ML output into `DetectedCard` values.
///
/// YOLOv8n exported with `nms=False` produces a single MultiArray output
/// of shape [1, 5, 8400]:
///   - dimension 1, index 0–3: cx, cy, w, h  (normalized 0–1, relative to input size)
///   - dimension 1, index 4:   class confidence for the single "card" class
///   - dimension 2: 8400 anchor slots
///
/// Coordinate system: YOLOv8 normalized coords have origin at top-left,
/// x right, y down — matching Vision's `VNRecognizedObjectObservation`
/// after a Y-flip from Vision's bottom-left origin.
///
/// The decoder:
///   1. Iterates all 8400 slots, discards those below `confidenceThreshold`.
///   2. Converts cx/cy/w/h → CGRect (top-left origin, normalized).
///   3. Applies IoU-based NMS (`iouThreshold`) to remove duplicates.
///   4. Converts surviving boxes to `DetectedCard` with axis-aligned quads.
struct YOLODecoder {

    // MARK: - Configuration

    /// Minimum class confidence to keep a candidate box.
    var confidenceThreshold: Float = 0.25

    /// IoU threshold above which two boxes are considered duplicates (NMS).
    var iouThreshold: CGFloat = 0.45

    // MARK: - Public

    /// Decode a raw YOLOv8n output MLMultiArray into DetectedCards.
    ///
    /// - Parameters:
    ///   - output: The model's output MultiArray, shape [1, 5, 8400].
    ///   - timestamp: Frame timestamp to stamp on each DetectedCard.
    /// - Returns: Filtered, NMS-deduplicated DetectedCard array.
    func decode(output: MLMultiArray, timestamp: TimeInterval) -> [DetectedCard] {
        // Shape: [1, 5, 8400] — strides let us index as [batch, feature, anchor]
        let anchors = output.shape[2].intValue   // 8400
        let strides = output.strides

        let batchStride   = strides[0].intValue
        let featureStride = strides[1].intValue
        let anchorStride  = strides[2].intValue

        let ptr = output.dataPointer.bindMemory(to: Float.self, capacity: output.count)

        var candidates: [(box: CGRect, confidence: Float)] = []

        for a in 0..<anchors {
            let base = 0 * batchStride + a * anchorStride
            let cx  = ptr[base + 0 * featureStride]
            let cy  = ptr[base + 1 * featureStride]
            let w   = ptr[base + 2 * featureStride]
            let h   = ptr[base + 3 * featureStride]
            let conf = ptr[base + 4 * featureStride]

            guard conf >= confidenceThreshold else { continue }

            // Convert cx/cy/w/h (YOLO top-left origin, y down) → CGRect in Vision space
            // (bottom-left origin, y up) by flipping: visionY = 1 - yoloY
            let x = CGFloat(cx - w / 2)
            let yTop = CGFloat(cy - h / 2)
            let yFlipped = 1.0 - yTop - CGFloat(h)   // flip to Vision bottom-left origin
            let rect = CGRect(x: x, y: yFlipped, width: CGFloat(w), height: CGFloat(h))
                .clamped()

            guard rect.width > 0.01, rect.height > 0.01 else { continue }
            candidates.append((box: rect, confidence: conf))
        }

        // NMS — sort by confidence descending, suppress overlapping boxes
        let sorted = candidates.sorted { $0.confidence > $1.confidence }
        var accepted: [(box: CGRect, confidence: Float)] = []
        for candidate in sorted {
            let isDuplicate = accepted.contains {
                RectangleFilter.iou(candidate.box, $0.box) > iouThreshold
            }
            if !isDuplicate {
                accepted.append(candidate)
            }
        }

        // Sort top-left → bottom-right (matches RectangleFilter spatial sort)
        let sorted2 = accepted.sorted { a, b in
            if abs(a.box.minY - b.box.minY) > 0.05 { return a.box.minY < b.box.minY }
            return a.box.minX < b.box.minX
        }

        return sorted2.map { DetectedCard(boundingBox: $0.box,
                                          confidence: $0.confidence,
                                          timestamp: timestamp) }
    }
}

// MARK: - CGRect helpers

private extension CGRect {
    /// Clamp all coordinates to [0, 1].
    func clamped() -> CGRect {
        let x = max(0, minX)
        let y = max(0, minY)
        let w = min(maxX, 1) - x
        let h = min(maxY, 1) - y
        return CGRect(x: x, y: y, width: max(0, w), height: max(0, h))
    }
}

// MARK: - DetectedCard from axis-aligned box

extension DetectedCard {
    /// Creates a DetectedCard from an axis-aligned bounding box.
    /// The four corner points are derived from the box corners directly.
    init(boundingBox: CGRect, confidence: Float, timestamp: TimeInterval) {
        self.init(
            boundingBox: boundingBox,
            topLeft:     CGPoint(x: boundingBox.minX, y: boundingBox.maxY),
            topRight:    CGPoint(x: boundingBox.maxX, y: boundingBox.maxY),
            bottomRight: CGPoint(x: boundingBox.maxX, y: boundingBox.minY),
            bottomLeft:  CGPoint(x: boundingBox.minX, y: boundingBox.minY),
            confidence:  confidence,
            timestamp:   timestamp
        )
    }
}
