import CoreGraphics
import UIKit
import Vision

/// Result of on-device card detection and cropping.
struct CardCropResult {
    /// Individual card crops extracted from the source image.
    let crops: [UIImage]
    /// Number of candidate regions found before cropping.
    let detectedCount: Int
}

/// On-device card detection and cropping using the Vision framework.
///
/// Detects likely MTG card regions in a captured image by:
/// 1. Running rectangle detection via VNDetectRectanglesRequest
/// 2. Filtering by MTG-like aspect ratio (2.5:3.5 ≈ 0.714) with tolerance
/// 3. Suppressing heavily overlapping duplicates (IoU-based)
/// 4. Cropping each accepted region with mild padding and perspective correction
///
/// A minimum confidence threshold is applied so that uncertain detections are
/// silently dropped rather than generating noisy speculative crops.
final class CardCropService {

    // MARK: - Constants

    /// Standard MTG card portrait aspect ratio (width / height).
    private static let targetAspectRatio: CGFloat = 2.5 / 3.5   // ≈ 0.714

    /// How far the detected aspect ratio may deviate from the target (relative).
    private static let aspectRatioTolerance: CGFloat = 0.28

    /// Minimum Vision rectangle confidence to accept a detection.
    private static let minVisionConfidence: Float = 0.4

    /// IoU threshold above which two regions are considered duplicates.
    private static let iouThreshold: CGFloat = 0.45

    /// Fraction of the shorter crop dimension added as padding on each side.
    private static let cropPadding: CGFloat = 0.03

    // MARK: - Public API

    /// Detects MTG card regions in `image` and returns individual crops.
    ///
    /// - Returns: A `CardCropResult` with `crops` ordered top-left to
    ///   bottom-right. Returns an empty result (not an error) when no usable
    ///   cards are found.
    func detectAndCrop(image: UIImage) async -> CardCropResult {
        guard let cgImage = image.cgImage else {
            return CardCropResult(crops: [], detectedCount: 0)
        }

        let observations = await runRectangleDetection(on: cgImage)
        let filtered = filterObservations(observations, imageSize: CGSize(width: cgImage.width, height: cgImage.height))

        var crops: [UIImage] = []
        for obs in filtered {
            if let crop = perspectiveCrop(cgImage: cgImage, observation: obs, originalImage: image) {
                crops.append(crop)
            }
        }

        return CardCropResult(crops: crops, detectedCount: filtered.count)
    }

    // MARK: - Detection

    private func runRectangleDetection(on cgImage: CGImage) async -> [VNRectangleObservation] {
        await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, _ in
                let results = (request.results as? [VNRectangleObservation]) ?? []
                continuation.resume(returning: results)
            }
            // Allow up to 10 cards in a single image (e.g. 3×3 binder page).
            request.maximumObservations = 10
            request.minimumConfidence = Self.minVisionConfidence
            request.minimumAspectRatio = Float(Self.targetAspectRatio * (1 - Self.aspectRatioTolerance))
            request.maximumAspectRatio = Float(Self.targetAspectRatio * (1 + Self.aspectRatioTolerance))

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Filtering

    private func filterObservations(
        _ observations: [VNRectangleObservation],
        imageSize: CGSize
    ) -> [VNRectangleObservation] {
        // Sort by descending confidence so higher-confidence detections win ties.
        let sorted = observations
            .filter { $0.confidence >= Self.minVisionConfidence }
            .sorted { $0.confidence > $1.confidence }

        var accepted: [VNRectangleObservation] = []
        for obs in sorted {
            let isDuplicate = accepted.contains { existing in
                iou(obs, existing, imageSize: imageSize) > Self.iouThreshold
            }
            if !isDuplicate {
                accepted.append(obs)
            }
        }

        // Re-sort accepted regions top-left → bottom-right for stable ordering.
        accepted.sort { a, b in
            let ay = a.boundingBox.minY
            let by = b.boundingBox.minY
            if abs(ay - by) > 0.05 { return ay < by }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        return accepted
    }

    // MARK: - Cropping

    /// Applies perspective-corrected crop using the four detected corners.
    private func perspectiveCrop(
        cgImage: CGImage,
        observation: VNRectangleObservation,
        originalImage: UIImage
    ) -> UIImage? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Vision normalised coordinates: origin bottom-left → flip to top-left.
        func flip(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * imageWidth, y: (1 - p.y) * imageHeight)
        }

        let tl = flip(observation.topLeft)
        let tr = flip(observation.topRight)
        let br = flip(observation.bottomRight)
        let bl = flip(observation.bottomLeft)

        // Expand quad outward by padding fraction of the shorter side.
        let boundW = max(distance(tl, tr), distance(bl, br))
        let boundH = max(distance(tl, bl), distance(tr, br))
        let pad = min(boundW, boundH) * Self.cropPadding

        let expanded = expandQuad(tl: tl, tr: tr, br: br, bl: bl, by: pad, in: CGSize(width: imageWidth, height: imageHeight))

        // Target output size preserving aspect ratio.
        let outWidth = max(boundW + pad * 2, 1)
        let outHeight = max(outWidth / Self.targetAspectRatio, 1)

        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: expanded.tl), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: expanded.tr), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: expanded.br), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: expanded.bl), forKey: "inputBottomLeft")

        guard let outputCIImage = filter.outputImage else { return nil }

        let context = CIContext()
        let outputRect = CGRect(x: 0, y: 0, width: outWidth, height: outHeight)
        // Scale the corrected image to the output rect.
        let scaled = outputCIImage.transformed(
            by: CGAffineTransform(
                scaleX: outWidth / outputCIImage.extent.width,
                y: outHeight / outputCIImage.extent.height
            )
        )
        guard let cgCrop = context.createCGImage(scaled, from: outputRect) else { return nil }

        return UIImage(cgImage: cgCrop, scale: originalImage.scale, orientation: .up)
    }

    // MARK: - Geometry helpers

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private struct Quad {
        var tl, tr, br, bl: CGPoint
    }

    private func expandQuad(tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint, by pad: CGFloat, in size: CGSize) -> Quad {
        let cx = (tl.x + tr.x + br.x + bl.x) / 4
        let cy = (tl.y + tr.y + br.y + bl.y) / 4

        func expand(_ p: CGPoint) -> CGPoint {
            let dx = p.x - cx
            let dy = p.y - cy
            let len = sqrt(dx * dx + dy * dy)
            guard len > 0 else { return p }
            let nx = dx / len
            let ny = dy / len
            let ex = max(0, min(size.width - 1, p.x + nx * pad))
            let ey = max(0, min(size.height - 1, p.y + ny * pad))
            return CGPoint(x: ex, y: ey)
        }

        return Quad(tl: expand(tl), tr: expand(tr), br: expand(br), bl: expand(bl))
    }

    /// Intersection-over-union for two VNRectangleObservations using their boundingBox.
    private func iou(_ a: VNRectangleObservation, _ b: VNRectangleObservation, imageSize: CGSize) -> CGFloat {
        let ra = a.boundingBox
        let rb = b.boundingBox
        let ix = max(0, min(ra.maxX, rb.maxX) - max(ra.minX, rb.minX))
        let iy = max(0, min(ra.maxY, rb.maxY) - max(ra.minY, rb.minY))
        let intersection = ix * iy
        let union = ra.width * ra.height + rb.width * rb.height - intersection
        return union > 0 ? intersection / union : 0
    }
}
