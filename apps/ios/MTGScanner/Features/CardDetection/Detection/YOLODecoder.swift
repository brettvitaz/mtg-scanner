import CoreGraphics
import CoreML
import Vision

/// Decodes raw YOLOv8n Core ML output into `DetectedCard` values.
///
/// YOLOv8n exported with `nms=False` produces a single MultiArray output
/// of shape [1, 5, 8400]:
///   - dimension 1, index 0–3: cx, cy, w, h  (pixel space, 0–640 in the model's 640×640 input)
///   - dimension 1, index 4:   class confidence for the single "card" class
///   - dimension 2: 8400 anchor slots
///
/// Coordinate pipeline:
///   Camera → native landscape pixel buffer (e.g. 1920×1080)
///   VNImageRequestHandler (no orientation) → passes buffer as-is
///   VNCoreMLRequest(.scaleFill) → scales to fill 640×640, cropping the longer dimension
///
/// Output coordinates are in AVFoundation normalized video space (bottom-left origin, 0–1)
/// so `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)` can map
/// them directly to screen coordinates without any device-specific hardcoding.
///
/// The decoder:
///   1. Iterates all 8400 slots, discards those below `confidenceThreshold`.
///   2. Converts pixel coords → model-normalized (0–1), then undoes scaleFill crop
///      using actual buffer dimensions to get normalized video coords (bottom-left origin).
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
    ///   - bufferWidth: Width of the source pixel buffer in pixels.
    ///   - bufferHeight: Height of the source pixel buffer in pixels.
    ///   - timestamp: Frame timestamp to stamp on each DetectedCard.
    /// - Returns: Filtered, NMS-deduplicated DetectedCard array, coordinates in
    ///   AVFoundation normalized video space (bottom-left origin, 0–1).
    func decode(output: MLMultiArray, bufferWidth: Int, bufferHeight: Int, timestamp: TimeInterval) -> [DetectedCard] {
        // Shape: [1, 5, 8400] — strides let us index as [batch, feature, anchor]
        let anchors = output.shape[2].intValue   // 8400
        let strides = output.strides

        let batchStride   = strides[0].intValue
        let featureStride = strides[1].intValue
        let anchorStride  = strides[2].intValue

        let ptr = output.dataPointer.bindMemory(to: Float.self, capacity: output.count)

        // Compute scaleFill crop offsets from actual buffer dimensions.
        // scaleFill scales the buffer to fill the model's 640×640 square by the shorter
        // dimension, then center-crops the longer dimension.
        // bufferW/H are the native pixel buffer dimensions (e.g. 1920×1080 landscape).
        let bW = Float(bufferWidth)
        let bH = Float(bufferHeight)
        let modelSize: Float = 640.0
        // Scale factor: shorter dimension fills modelSize
        let scale = modelSize / min(bW, bH)
        let scaledW = bW * scale   // dimension after scaling
        let scaledH = bH * scale
        // Crop: longer scaled dimension is center-cropped to modelSize
        let cropX = max(0, (scaledW - modelSize) / 2.0)  // pixels cropped from each side horizontally
        let cropY = max(0, (scaledH - modelSize) / 2.0)  // pixels cropped from each side vertically
        // To undo: model coord → original buffer pixel = (modelCoord + cropOffset) / scale
        // Then normalize to [0,1]: divide by bW or bH

        var candidates: [(box: CGRect, confidence: Float)] = []

        for a in 0..<anchors {
            let base = 0 * batchStride + a * anchorStride
            let cx  = ptr[base + 0 * featureStride]
            let cy  = ptr[base + 1 * featureStride]
            let w   = ptr[base + 2 * featureStride]
            let h   = ptr[base + 3 * featureStride]
            let conf = ptr[base + 4 * featureStride]

            guard conf >= confidenceThreshold else { continue }

            // Convert model pixel coords (0–640) back to normalized buffer coords (0–1).
            // Undo scaleFill: add crop offset, divide by scale, divide by buffer dimension.
            // Result: normalized coords in AVFoundation video space (top-left origin here;
            // we flip Y below to get bottom-left origin for layerRectConverted).
            let bufPxCX = (cx + cropX) / scale   // center x in buffer pixels
            let bufPxCY = (cy + cropY) / scale   // center y in buffer pixels
            let bufPxW  = w  / scale             // width in buffer pixels
            let bufPxH  = h  / scale             // height in buffer pixels

            let ncx = bufPxCX / bW               // normalized 0–1, top-left origin
            let ncy = bufPxCY / bH
            let nw  = bufPxW  / bW
            let nh  = bufPxH  / bH

            // AVFoundation normalized video space uses bottom-left origin (y flipped).
            let x = CGFloat(ncx - nw / 2)
            let y = CGFloat(1.0 - (ncy + nh / 2))   // flip Y: top-left → bottom-left origin
            let rect = CGRect(x: x, y: y, width: CGFloat(nw), height: CGFloat(nh))
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

        let cards = sorted2.map { DetectedCard(boundingBox: $0.box,
                                               confidence: $0.confidence,
                                               timestamp: timestamp) }
        for (i, c) in cards.enumerated() {
            let b = c.boundingBox
            print(String(format: "[YOLO] 📦 card[%d] x=%.3f y=%.3f w=%.3f h=%.3f conf=%.2f",
                         i, b.minX, b.minY, b.width, b.height, c.confidence))
        }
        return cards
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
        // YOLO uses top-left origin (y increases downward), so:
        // topLeft = (minX, minY), bottomRight = (maxX, maxY)
        self.init(
            boundingBox: boundingBox,
            topLeft:     CGPoint(x: boundingBox.minX, y: boundingBox.minY),
            topRight:    CGPoint(x: boundingBox.maxX, y: boundingBox.minY),
            bottomRight: CGPoint(x: boundingBox.maxX, y: boundingBox.maxY),
            bottomLeft:  CGPoint(x: boundingBox.minX, y: boundingBox.maxY),
            confidence:  confidence,
            timestamp:   timestamp
        )
    }
}
