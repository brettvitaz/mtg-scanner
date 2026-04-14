import CoreVideo
import Foundation

/// Detects scene changes between camera frames by comparing sparse luminance samples.
///
/// Used in Auto Scan mode to distinguish a new card drop (large scene change) from
/// an unchanged bin (same card or empty).
///
/// Sampling every `sampleStride` pixels in both axes gives a coarse-but-fast
/// approximation of overall frame luminance, robust to JPEG compression and minor
/// lighting flicker.
struct FrameDifferenceAnalyzer {

    /// Pixel spacing for the sparse sampling grid.
    let sampleStride: Int

    init(sampleStride: Int = 16) {
        self.sampleStride = max(sampleStride, 1)
    }

    // MARK: - Sampling

    /// Samples luminance values from a BGRA pixel buffer on a coarse grid.
    ///
    /// Returns an empty array if the buffer cannot be locked.
    func sample(_ pixelBuffer: CVPixelBuffer) -> [UInt8] {
        sample(pixelBuffer, zone: nil)
    }

    /// Samples luminance values from a BGRA pixel buffer within a specific zone.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The pixel buffer to sample from
    ///   - zone: Normalized rect (0-1) in Vision coordinates (bottom-left origin) defining
    ///           the region to sample. If nil, samples the entire frame.
    /// - Returns: Array of luminance samples, or empty array if buffer cannot be locked
    func sample(_ pixelBuffer: CVPixelBuffer, zone: CGRect?) -> [UInt8] {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bounds = pixelBounds(for: zone, width: width, height: height)

        return sampleRegion(
            base: base,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            bounds: bounds
        )
    }

    private func pixelBounds(for zone: CGRect?, width: Int, height: Int) -> CGRect {
        guard let zone = zone else { return CGRect(x: 0, y: 0, width: width, height: height) }
        // Convert from Vision normalized coordinates (bottom-left origin) to pixel coordinates
        // Vision: (0,0) at bottom-left, y goes up; Pixel buffer: (0,0) at top-left, y goes down
        let pixelMinX = zone.minX * CGFloat(width)
        let pixelMaxX = zone.maxX * CGFloat(width)
        let pixelMinY = (1.0 - zone.maxY) * CGFloat(height)
        let pixelMaxY = (1.0 - zone.minY) * CGFloat(height)
        let bounds = CGRect(
            x: max(0, pixelMinX),
            y: max(0, pixelMinY),
            width: min(CGFloat(width), pixelMaxX) - max(0, pixelMinX),
            height: min(CGFloat(height), pixelMaxY) - max(0, pixelMinY)
        )
        #if DEBUG
        print("[FrameDifference] Zone: \(zone), Pixel bounds: \(bounds), Buffer: \(width)x\(height)")
        #endif
        return bounds
    }

    private func sampleRegion(
        base: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        bounds: CGRect
    ) -> [UInt8] {
        let rawPtr = base.assumingMemoryBound(to: UInt8.self)
        var samples: [UInt8] = []
        let minY = Int(bounds.minY)
        let maxY = Int(bounds.maxY)
        let minX = Int(bounds.minX)
        let maxX = Int(bounds.maxX)
        var y = minY
        while y < maxY {
            var x = minX
            while x < maxX {
                let idx = y * bytesPerRow + x * 4
                // BGRA layout: B=idx+0, G=idx+1, R=idx+2
                // Rec. 601 luma coefficients scaled to integer: 0.299R + 0.587G + 0.114B
                let luma = (77 * Int(rawPtr[idx + 2]) + 150 * Int(rawPtr[idx + 1]) + 29 * Int(rawPtr[idx])) >> 8
                samples.append(UInt8(clamping: luma))
                x += sampleStride
            }
            y += sampleStride
        }
        return samples
    }

    // MARK: - Difference

    /// Returns a normalized difference score in [0, 1].
    ///
    /// A score near 0 means the frames are visually identical; near 1 means maximally
    /// different. Returns 0 if the sample arrays have different lengths or are empty.
    func difference(from a: [UInt8], to b: [UInt8]) -> Float {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var total: Int = 0
        for i in a.indices {
            total += abs(Int(a[i]) - Int(b[i]))
        }
        return Float(total) / Float(a.count * 255)
    }
}
