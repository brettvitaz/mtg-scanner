import AVFoundation
import CoreVideo

/// Detects when a new card is dropped into the scanning station.
///
/// Combines two signals on each camera frame:
/// 1. **YOLO detection** — confirms a card object is visible (not just bin geometry).
/// 2. **Frame differencing** — confirms the scene changed significantly relative to
///    the last captured frame (i.e., a new card was placed, not the same card).
///
/// A "new card" event fires only when both signals agree.  After a capture, call
/// `markCaptured()` so the next card drop is measured relative to the new reference.
///
/// Threading: `processFrame(_:)` is safe to call from any queue.  Internal work runs
/// on a dedicated serial queue.  `onNewCardSignal` is always called on the main queue.
final class CardPresenceTracker {

    // MARK: - Configuration

    /// Minimum frame-difference score (0–1) to count as a meaningful scene change.
    var sceneChangeThreshold: Float = 0.03

    /// Minimum YOLO confidence for a card to be considered present.
    var confidenceThreshold: Float = 0.5 {
        didSet { detector?.confidenceThreshold = confidenceThreshold }
    }

    // MARK: - Callbacks

    /// Called on the main queue when a new card is detected.
    ///
    /// The `CGRect?` is the highest-confidence bounding box in normalized top-left-origin
    /// image coordinates, or `nil` if position data is unavailable.
    var onNewCardSignal: ((CGRect?) -> Void)?

    // MARK: - Private

    private let detector: YOLOCardDetector?
    private let analyzer = FrameDifferenceAnalyzer()
    private let presenceQueue = DispatchQueue(
        label: "com.mtgscanner.cardpresence",
        qos: .userInitiated
    )
    private var isProcessing = false
    private var referenceSamples: [UInt8] = []
    private var lastSamples: [UInt8] = []

    // MARK: - Init

    init(detector: YOLOCardDetector?) {
        self.detector = detector
        self.detector?.confidenceThreshold = confidenceThreshold
    }

    // MARK: - Reference Management

    /// Updates the reference frame to the most recently processed frame.
    ///
    /// Call this immediately after each successful capture so the next card drop
    /// is evaluated relative to the newly captured card's appearance.
    func markCaptured() {
        presenceQueue.async { [weak self] in
            guard let self else { return }
            self.referenceSamples = self.lastSamples
        }
    }

    // MARK: - Frame Processing

    /// Process a camera frame. Drops the frame if a previous frame is still being processed.
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        presenceQueue.async { [weak self] in
            guard let self, !self.isProcessing else { return }
            self.isProcessing = true
            self.process(pixelBuffer: pixelBuffer)
            self.isProcessing = false
        }
    }

    private func process(pixelBuffer: CVPixelBuffer) {
        let samples = analyzer.sample(pixelBuffer)
        lastSamples = samples

        let diff = referenceSamples.isEmpty
            ? 1.0  // no reference yet — always treat as changed
            : analyzer.difference(from: referenceSamples, to: samples)

        guard diff >= sceneChangeThreshold else { return }

        let boxes = detector?.detect(in: pixelBuffer) ?? []
        guard !boxes.isEmpty else { return }

        let bestBox = boxes.max(by: { $0.confidence < $1.confidence })?.rect

        DispatchQueue.main.async { [weak self] in
            self?.onNewCardSignal?(bestBox)
        }
    }
}
