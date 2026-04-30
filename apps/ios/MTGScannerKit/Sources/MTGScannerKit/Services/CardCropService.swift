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

/// Optional detector context used to refine still-image crop selection.
struct CardCropHint: Sendable {
    /// Normalized YOLO box in top-left-origin coordinates.
    let yoloBoxTopLeft: CGRect?
    /// Prefer the single best matching crop instead of returning all card crops.
    let preferSingleCrop: Bool

    init(yoloBoxTopLeft: CGRect? = nil, preferSingleCrop: Bool = false) {
        self.yoloBoxTopLeft = yoloBoxTopLeft
        self.preferSingleCrop = preferSingleCrop
    }
}

/// On-device card detection and cropping using the Vision framework.
///
/// Detects likely MTG card regions in a captured image by:
/// 1. Running rectangle detection via VNDetectRectanglesRequest
/// 2. Filtering by MTG-like aspect ratio (2.5:3.5 ≈ 0.714) with tolerance
/// 3. Suppressing heavily overlapping duplicates (IoU-based)
/// 4. Cropping each accepted region with perspective correction
final class CardCropService: @unchecked Sendable {

    private static let cropPadding: CGFloat = 0.01
    private static let hintROIPadding: CGFloat = 0.18
    private static let cardAspectRatio = RectangleFilter.targetAspectRatio
    private let rectangleFilter = RectangleFilter(configuration: .crop)
    private let ciContext = CIContext()

    // MARK: - Public API

    /// Detects MTG card regions in `image` and returns individual crops.
    func detectAndCrop(image: UIImage, hint: CardCropHint? = nil) async -> CardCropResult {
        // Step 1: Normalize to an upright UIImage whose cgImage pixels match
        // the visual orientation. This eliminates ALL orientation complexity
        // from every downstream step.
        let upright = normalizedImage(image)
        guard let cgImage = upright.cgImage else {
            return CardCropResult(crops: [], detectedCount: 0)
        }

        // Step 2: Run Vision rectangle detection on upright pixels.
        let yoloHint = hint?.yoloBoxTopLeft
        let visionHint = yoloHint.map(Self.visionBox(fromYoloBox:))
        let observations = detectRectangles(in: cgImage, regionHint: visionHint)
        let ranked = rectangleFilter.rank(
            observations,
            isLandscape: false,
            visionHint: visionHint,
            preferSingle: hint?.preferSingleCrop == true
        )

        // Step 3: Perspective-correct and crop each detected card.
        let crops = ranked.compactMap { cropCard(from: cgImage, observation: $0) }

        if crops.isEmpty,
           let fallbackBox = yoloHint,
           let fallbackCrop = axisAlignedCrop(from: cgImage, yoloBox: fallbackBox) {
            return CardCropResult(crops: [fallbackCrop], detectedCount: 0)
        }

        return CardCropResult(crops: crops, detectedCount: ranked.count)
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

    private func detectRectangles(in cgImage: CGImage, regionHint: CGRect?) -> [VNRectangleObservation] {
        guard let regionHint else {
            return runRectangleDetection(in: cgImage, regionOfInterest: nil)
        }

        let roiObservations = runRectangleDetection(
            in: cgImage,
            regionOfInterest: Self.expandedRect(regionHint, by: Self.hintROIPadding)
        )
        let fullImageObservations = runRectangleDetection(in: cgImage, regionOfInterest: nil)
        return roiObservations + fullImageObservations
    }

    private func runRectangleDetection(in cgImage: CGImage, regionOfInterest: CGRect?) -> [VNRectangleObservation] {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 10
        request.minimumConfidence = RectangleFilter.minConfidence
        request.minimumAspectRatio = RectangleFilter.visionMinAspectRatio
        request.maximumAspectRatio = RectangleFilter.visionMaxAspectRatio
        request.quadratureTolerance = 15.0
        if let regionOfInterest {
            request.regionOfInterest = regionOfInterest
        }

        // CGImage is already upright, so no orientation hint needed.
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return (request.results as? [VNRectangleObservation]) ?? []
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
        return canonicalPortraitCardImage(UIImage(cgImage: cgResult))
    }

    private func axisAlignedCrop(from cgImage: CGImage, yoloBox: CGRect) -> UIImage? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let clamped = Self.clamped(yoloBox)
        guard clamped.width > 0, clamped.height > 0 else { return nil }

        let pixelRect = CGRect(
            x: clamped.minX * imageWidth,
            y: clamped.minY * imageHeight,
            width: clamped.width * imageWidth,
            height: clamped.height * imageHeight
        )
        let pad = min(pixelRect.width, pixelRect.height) * Self.cropPadding
        let paddedRect = CGRect(
            x: max(0, pixelRect.minX - pad),
            y: max(0, pixelRect.minY - pad),
            width: min(imageWidth, pixelRect.maxX + pad) - max(0, pixelRect.minX - pad),
            height: min(imageHeight, pixelRect.maxY + pad) - max(0, pixelRect.minY - pad)
        )
        guard paddedRect.width > 0, paddedRect.height > 0,
              let cropped = cgImage.cropping(to: paddedRect) else { return nil }
        return canonicalPortraitCardImage(UIImage(cgImage: cropped))
    }

    // MARK: - Geometry Helpers

    private static func visionBox(fromYoloBox box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1.0 - box.maxY, width: box.width, height: box.height)
    }

    private static func expandedRect(_ rect: CGRect, by fraction: CGFloat) -> CGRect {
        clamped(rect.insetBy(dx: -rect.width * fraction, dy: -rect.height * fraction))
    }

    private static func clamped(_ rect: CGRect) -> CGRect {
        let minX = max(0, rect.minX)
        let minY = max(0, rect.minY)
        let maxX = min(1, rect.maxX)
        let maxY = min(1, rect.maxY)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

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

    private func canonicalPortraitCardImage(_ image: UIImage) -> UIImage {
        let portrait = image.size.width > image.size.height ? rotateRight(image) : image
        return resizeToCardAspect(portrait)
    }

    private func rotateRight(_ image: UIImage) -> UIImage {
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: .pi / 2)
            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }
    }

    private func resizeToCardAspect(_ image: UIImage) -> UIImage {
        guard image.size.width > 0, image.size.height > 0 else { return image }
        let currentRatio = image.size.width / image.size.height
        guard abs(currentRatio - Self.cardAspectRatio) > 0.005 else { return image }

        let targetSize: CGSize
        if currentRatio > Self.cardAspectRatio {
            targetSize = CGSize(width: image.size.height * Self.cardAspectRatio, height: image.size.height)
        } else {
            targetSize = CGSize(width: image.size.width, height: image.size.width / Self.cardAspectRatio)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
