import CoreVideo
import Foundation

/// Detects scene changes between camera frames by comparing sparse luminance samples.
///
/// Used in Quick Scan mode to distinguish a new card drop (large scene change) from
/// an unchanged bin (same card or empty).
///
/// Sampling every `sampleStride` pixels in both axes gives a coarse-but-fast
/// approximation of overall frame luminance, robust to JPEG compression and minor
/// lighting flicker.
struct FrameDifferenceAnalyzer {

    /// Pixel spacing for the sparse sampling grid.
    let sampleStride: Int

    init(sampleStride: Int = 16) {
        self.sampleStride = sampleStride
    }

    // MARK: - Sampling

    /// Samples luminance values from a BGRA pixel buffer on a coarse grid.
    ///
    /// Returns an empty array if the buffer cannot be locked.
    func sample(_ pixelBuffer: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let rawPtr = base.assumingMemoryBound(to: UInt8.self)

        var samples: [UInt8] = []
        var y = 0
        while y < height {
            var x = 0
            while x < width {
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
