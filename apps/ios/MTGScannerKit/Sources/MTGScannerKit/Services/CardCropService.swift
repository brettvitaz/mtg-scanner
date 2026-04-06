import CoreGraphics
import CoreImage
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
/// 4. Cropping each accepted region with perspective correction
final class CardCropService {

    private static let cropPadding: CGFloat = 0.03
    private let rectangleFilter = RectangleFilter()
    private let ciContext = CIContext()

    // MARK: - Public API

    /// Detects MTG card regions in `image` and returns individual crops.
    func detectAndCrop(image: UIImage) async -> CardCropResult {
        // Step 1: Normalize to an upright UIImage whose cgImage pixels match
        // the visual orientation. This eliminates ALL orientation complexity
        // from every downstream step.
        let upright = normalizedImage(image)
        guard let cgImage = upright.cgImage else {
            return CardCropResult(crops: [], detectedCount: 0)
        }

        // Step 2: Run Vision rectangle detection on upright pixels.
        let observations = await detectRectangles(in: cgImage)
        let filtered = rectangleFilter.filter(observations, isLandscape: false)

        // Step 3: Perspective-correct and crop each detected card.
        let crops = filtered.compactMap { cropCard(from: cgImage, observation: $0) }

        return CardCropResult(crops: crops, detectedCount: filtered.count)
    }

    // MARK: - Orientation Normalization

    /// Redraws the image so that cgImage pixels are upright (.up orientation).
    /// If already upright, returns the original to avoid unnecessary work.
    private func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // MARK: - Rectangle Detection

    private func detectRectangles(in cgImage: CGImage) async -> [VNRectangleObservation] {
        await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, _ in
                let results = (request.results as? [VNRectangleObservation]) ?? []
                continuation.resume(returning: results)
            }
            request.maximumObservations = 10
            request.minimumConfidence = RectangleFilter.minConfidence
            request.minimumAspectRatio = RectangleFilter.visionMinAspectRatio
            request.maximumAspectRatio = RectangleFilter.visionMaxAspectRatio

            // CGImage is already upright, so no orientation hint needed.
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Perspective Crop

    /// Applies CIPerspectiveCorrection to extract a single card from the image.
    ///
    /// Coordinate convention:
    /// - Vision returns normalized coords in [0,1] with bottom-left origin.
    /// - CIImage(cgImage:) also uses bottom-left origin.
    /// - Therefore we scale Vision coords to pixel dimensions directly (no Y-flip).
    private func cropCard(
        from cgImage: CGImage,
        observation: VNRectangleObservation
    ) -> UIImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)

        // Scale normalized Vision coords → CIImage pixel coords (both bottom-left origin).
        let topLeft     = CGPoint(x: observation.topLeft.x * w, y: observation.topLeft.y * h)
        let topRight    = CGPoint(x: observation.topRight.x * w, y: observation.topRight.y * h)
        let bottomRight = CGPoint(x: observation.bottomRight.x * w, y: observation.bottomRight.y * h)
        let bottomLeft  = CGPoint(x: observation.bottomLeft.x * w, y: observation.bottomLeft.y * h)

        // Apply padding.
        let quadW = max(dist(topLeft, topRight), dist(bottomLeft, bottomRight))
        let quadH = max(dist(topLeft, bottomLeft), dist(topRight, bottomRight))
        let pad = min(quadW, quadH) * Self.cropPadding
        let padded = padQuad(
            tl: topLeft, tr: topRight, br: bottomRight, bl: bottomLeft,
            by: pad, bounds: CGSize(width: w, height: h)
        )

        // CIPerspectiveCorrection expects CIImage coordinates (bottom-left origin).
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: padded.tl), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: padded.tr), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: padded.br), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: padded.bl), forKey: "inputBottomLeft")

        guard let output = filter.outputImage else { return nil }

        // Render the corrected image at its natural size.
        guard let cgResult = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgResult)
    }

    // MARK: - Geometry Helpers

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private struct Quad { var tl, tr, br, bl: CGPoint }

    private func padQuad(tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint,
                         by pad: CGFloat, bounds: CGSize) -> Quad {
        let cx = (tl.x + tr.x + br.x + bl.x) / 4
        let cy = (tl.y + tr.y + br.y + bl.y) / 4

        func expand(_ p: CGPoint) -> CGPoint {
            let dx = p.x - cx, dy = p.y - cy
            let len = hypot(dx, dy)
            guard len > 0 else { return p }
            return CGPoint(
                x: max(0, min(bounds.width, p.x + (dx / len) * pad)),
                y: max(0, min(bounds.height, p.y + (dy / len) * pad))
            )
        }
        return Quad(tl: expand(tl), tr: expand(tr), br: expand(br), bl: expand(bl))
    }
}
