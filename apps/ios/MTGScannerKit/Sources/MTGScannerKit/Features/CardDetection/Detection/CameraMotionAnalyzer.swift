import CoreImage
import CoreVideo
import Foundation
import OSLog
import Vision

/// Rejects confidently global camera translation, without vetoing local/identical-card placements.
/// Owned thumbnails and registration stay on CardPresenceTracker's serial queue.
final class CameraMotionAnalyzer {
    private lazy var context = CIContext(options: [.cacheIntermediates: false])
    private var reference: MotionThumbnail?
    private var globalFrames = 0
    private var matchingCorners = Set(0..<4)
    private var hasUnexplainedMotion = false
    private let logger = Logger(subsystem: "com.mtgscanner", category: "CameraMotion")

    func isCameraOnlyMotion(excluding card: CGRect) -> Bool {
        guard globalFrames >= 2, !hasUnexplainedMotion else { return false }
        let region = card.insetBy(dx: -0.025, dy: -0.025)
        let mirrored = CGRect(x: region.minX, y: 1 - region.maxY, width: region.width, height: region.height)
        // Excluding both vertical projections conservatively prevents storage orientation
        // from ever making card pixels qualify as independent background evidence.
        return MotionThumbnail.cornerRegions.indices.filter { index in
            let tile = MotionThumbnail.cornerRegions[index]
            return matchingCorners.contains(index) && !tile.intersects(region) && !tile.intersects(mirrored)
        }.count >= 2
    }

    func reset() {
        reference = nil
        globalFrames = 0
        matchingCorners = Set(0..<4)
        hasUnexplainedMotion = false
    }

    func setReference(_ pixelBuffer: CVPixelBuffer) {
        reset()
        reference = thumbnail(pixelBuffer)
    }

    func observe(_ pixelBuffer: CVPixelBuffer, threshold: Float) {
        guard let reference, let current = thumbnail(pixelBuffer),
              reference.width == current.width, reference.height == current.height,
              let referenceImage = reference.image, let currentImage = current.image else {
            hasUnexplainedMotion = true
            return
        }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: currentImage)
        do {
            try VNImageRequestHandler(cgImage: referenceImage).perform([request])
            if let transform = request.results?.first?.alignmentTransform,
               let corners = reference.globalTranslationCorners(of: current, transform: transform,
                                                                threshold: threshold) {
                matchingCorners.formIntersection(corners)
                globalFrames += 1
            } else {
                hasUnexplainedMotion = true
            }
        } catch {
            hasUnexplainedMotion = true
            #if DEBUG
            print("[CameraMotion] registration error: \(error.localizedDescription)")
            #endif
            logger.debug("Camera-motion registration inconclusive: \(error.localizedDescription)")
        }
    }

    private func thumbnail(_ pixelBuffer: CVPixelBuffer) -> MotionThumbnail? {
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = min(1, 128 / max(source.extent.width, source.extent.height))
        let width = Int(source.extent.width * scale), height = Int(source.extent.height * scale)
        guard width >= 32, height >= 32 else { return nil }
        let scaled = source.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale])
        var pixels = [UInt8](repeating: 0, count: width * height)
        context.render(scaled, toBitmap: &pixels, rowBytes: width,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        return MotionThumbnail(width: width, height: height, pixels: pixels)
    }
}

private struct MotionThumbnail {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    var image: CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static let cornerRegions = [CGRect(x: 0, y: 0, width: 0.25, height: 0.25),
                                CGRect(x: 0.75, y: 0, width: 0.25, height: 0.25),
                                CGRect(x: 0, y: 0.75, width: 0.25, height: 0.25),
                                CGRect(x: 0.75, y: 0.75, width: 0.25, height: 0.25)]

    func globalTranslationCorners(of current: Self, transform: CGAffineTransform, threshold: Float) -> Set<Int>? {
        var dx = transform.tx, dy = -transform.ty // Image-registration Y is opposite bitmap row order.
        guard dx.isFinite, dy.isFinite, hypot(dx, dy) >= 0.35,
              abs(dx) < CGFloat(width) * 0.1, abs(dy) < CGFloat(height) * 0.1 else { return nil }
        let inset = Int(ceil(max(abs(dx), abs(dy)))) + 2
        let bounds = CGRect(x: inset, y: inset, width: width - inset * 2, height: height - inset * 2)
        let refined = refinedTranslation(current, in: bounds, dx: dx, dy: dy)
        dx = refined.x
        dy = refined.y
        let whole = metrics(current, in: bounds, dx: dx, dy: dy)
        let tolerance = max(0.015, threshold)
        #if DEBUG
        print("[CameraMotion] shift=\(dx),\(dy) raw=\(whole.raw) aligned=\(whole.aligned)")
        #endif
        guard whole.aligned <= tolerance, whole.aligned < whole.raw * 0.5 else { return nil }
        // Texture and matching motion in multiple background corners distinguish camera shake
        // from an identical card sliding over its predecessor in the center of a still scene.
        let matching = Self.cornerRegions.indices.filter { index in
            let region = Self.cornerRegions[index]
            let tile = CGRect(x: region.minX * CGFloat(width), y: region.minY * CGFloat(height),
                              width: region.width * CGFloat(width), height: region.height * CGFloat(height))
                .intersection(bounds)
            let result = metrics(current, in: tile, dx: dx, dy: dy)
            return result.texture >= 0.01 && result.raw >= threshold * 0.5 &&
                result.aligned <= tolerance && result.aligned < result.raw * 0.5
        }
        #if DEBUG
        print("[CameraMotion] matching peripheral tiles=\(matching.count)")
        #endif
        return matching.count >= 2 ? Set(matching) : nil
    }

    private func refinedTranslation(_ current: Self, in bounds: CGRect, dx: CGFloat, dy: CGFloat) -> CGPoint {
        // Vision may quantize the small thumbnail's translation. Refine around its estimate
        // so subpixel ringdown is not mistaken for an unexplained local change.
        var best = CGPoint(x: dx, y: dy)
        var residual = metrics(current, in: bounds, dx: dx, dy: dy).aligned
        for horizontal in [CGFloat(-0.5), 0, 0.5] {
            for vertical in [CGFloat(-0.5), 0, 0.5] {
                let candidate = CGPoint(x: dx + horizontal, y: dy + vertical)
                let score = metrics(current, in: bounds, dx: candidate.x, dy: candidate.y).aligned
                if score < residual { residual = score; best = candidate }
            }
        }
        return best
    }

    private func metrics(_ current: Self, in rect: CGRect, dx: CGFloat, dy: CGFloat)
        -> MotionResidual {
        guard !rect.isEmpty, !rect.isNull else { return .unavailable }
        var raw: Float = 0, aligned: Float = 0, texture: Float = 0, count: Float = 0
        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 2) {
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 2) {
                let value = Float(pixels[y * width + x])
                raw += abs(value - Float(current.pixels[y * width + x]))
                aligned += abs(Float(current.pixels[y * width + x]) -
                    interpolated(x: CGFloat(x) + dx, y: CGFloat(y) + dy))
                let horizontal = abs(value - Float(pixels[y * width + min(x + 1, width - 1)]))
                let vertical = abs(value - Float(pixels[min(y + 1, height - 1) * width + x]))
                texture += max(horizontal, vertical)
                count += 255
            }
        }
        guard count > 0 else { return .unavailable }
        return MotionResidual(raw: raw / count, aligned: aligned / count, texture: texture / count)
    }

    private func interpolated(x: CGFloat, y: CGFloat) -> Float {
        let x = min(max(x, 0), CGFloat(width - 2)), y = min(max(y, 0), CGFloat(height - 2))
        let left = Int(x), top = Int(y)
        let horizontal = Float(x - CGFloat(left)), vertical = Float(y - CGFloat(top))
        let upper = Float(pixels[top * width + left]) * (1 - horizontal) +
            Float(pixels[top * width + left + 1]) * horizontal
        let lower = Float(pixels[(top + 1) * width + left]) * (1 - horizontal) +
            Float(pixels[(top + 1) * width + left + 1]) * horizontal
        return upper * (1 - vertical) + lower * vertical
    }
}

private struct MotionResidual {
    let raw: Float
    let aligned: Float
    let texture: Float
    static let unavailable = MotionResidual(raw: 1, aligned: 1, texture: 0)
}
