import UIKit

/// Crops a UIImage to a bounding box returned by the YOLO card detector.
///
/// YOLO boxes are normalized top-left-origin [0,1] and axis-aligned, so a simple
/// `CGImage.cropping(to:)` is sufficient — no perspective correction needed.
enum AutoScanCropHelper {

    private static let defaultPadding: CGFloat = 0.03

    /// Crop `image` to `normalizedRect` (YOLO top-left-origin, [0,1] coords).
    ///
    /// - Parameters:
    ///   - image: Source UIImage. Orientation is normalized before cropping.
    ///   - normalizedRect: Bounding box in YOLO coordinate space (x, y, width, height all in [0,1]).
    ///   - padding: Fractional padding applied uniformly around the box (default 3%).
    /// - Returns: Cropped UIImage, or `nil` if the rect is degenerate or the image has no cgImage.
    static func cropImage(
        _ image: UIImage,
        toNormalizedRect normalizedRect: CGRect,
        padding: CGFloat = defaultPadding
    ) -> UIImage? {
        guard normalizedRect.width > 0, normalizedRect.height > 0 else { return nil }
        let upright = normalizedImage(image)
        guard let cgImage = upright.cgImage else { return nil }
        return crop(cgImage: cgImage, toNormalizedRect: normalizedRect, padding: padding)
    }

    // MARK: - Orientation Normalization

    /// Redraws the image so cgImage pixels are upright (.up orientation).
    static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    // MARK: - Private

    private static func crop(
        cgImage: CGImage,
        toNormalizedRect normalizedRect: CGRect,
        padding: CGFloat
    ) -> UIImage? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Scale normalized coords to pixel coords (both top-left origin — no Y-flip needed).
        let pixelRect = CGRect(
            x: normalizedRect.minX * imageWidth,
            y: normalizedRect.minY * imageHeight,
            width: normalizedRect.width * imageWidth,
            height: normalizedRect.height * imageHeight
        )

        let pad = min(pixelRect.width, pixelRect.height) * padding
        let paddedRect = CGRect(
            x: max(0, pixelRect.minX - pad),
            y: max(0, pixelRect.minY - pad),
            width: min(imageWidth, pixelRect.maxX + pad) - max(0, pixelRect.minX - pad),
            height: min(imageHeight, pixelRect.maxY + pad) - max(0, pixelRect.minY - pad)
        )

        guard paddedRect.width > 0, paddedRect.height > 0 else { return nil }
        guard let cropped = cgImage.cropping(to: paddedRect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
