import CoreMedia
import CoreVideo
import MTGScannerKit
import UIKit

/// A ``CameraFrameSource`` that emits ``CVPixelBuffer``s decoded from bundled fixture images.
///
/// Used in preview/simulator builds (via ``FixtureCameraViewController``) to drive card
/// detection without a real camera. Images are decoded once at init; the emit path is
/// timer-based with no I/O.
///
/// - Note: Images are resized to `targetSize` (default 1920×1080, matching the production
///   session preset) so Vision receives correctly-sized input.
public final class FixtureFrameSource: CameraFrameSource, @unchecked Sendable {

    public var onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)?

    private let pixelBuffers: [CVPixelBuffer]
    private let frameInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.mtgscanner.fixture-frames", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var running = false
    private var index = 0

    // 1920×1080 matches CameraSessionManager's `.hd1920x1080` session preset.
    public static let targetSize = CGSize(width: 1920, height: 1080)

    /// Fixture image filenames bundled under `Resources/FixtureFrames/`.
    public static let fixtureNames: [String] = [
        "hand_held_card",
        "IMG_1609",
        "IMG_1610"
    ]

    /// - Parameter frameInterval: Seconds between emitted frames. Default is 0.2s (5 Hz), which is
    ///   intentionally slower than production 30 Hz — the goal is simulator UI verification, not
    ///   real-time performance, and the reduced rate keeps CPU overhead minimal during screenshotting.
    public init(frameInterval: TimeInterval = 0.2) {
        self.frameInterval = frameInterval
        self.pixelBuffers = Self.loadPixelBuffers()
    }

    public func start() {
        queue.sync {
            guard !self.pixelBuffers.isEmpty, !self.running, self.timer == nil else { return }
            self.running = true
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now(), repeating: self.frameInterval)
            t.setEventHandler { [weak self] in self?.emitNextFrame() }
            t.resume()
            self.timer = t
        }
    }

    public func stop() {
        queue.sync {
            self.running = false
            self.timer?.cancel()
            self.timer = nil
        }
    }

    private func emitNextFrame() {
        guard running, !pixelBuffers.isEmpty else { return }
        let buffer = pixelBuffers[index % pixelBuffers.count]
        index &+= 1
        let time = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        onPixelBuffer?(buffer, time)
    }

    // MARK: - Image loading

    private static func loadPixelBuffers() -> [CVPixelBuffer] {
        fixtureNames.compactMap { name in
            guard let url = Bundle.module.url(forResource: name, withExtension: nil)
                    ?? findBundleURL(name: name) else { return nil }
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            return pixelBuffer(from: image, size: targetSize)
        }
    }

    /// Fallback for common image extensions when the bundle URL lookup needs an explicit extension.
    public static func findBundleURL(name: String) -> URL? {
        for ext in ["jpg", "jpeg", "png"] {
            if let url = Bundle.module.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    public static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        guard let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
