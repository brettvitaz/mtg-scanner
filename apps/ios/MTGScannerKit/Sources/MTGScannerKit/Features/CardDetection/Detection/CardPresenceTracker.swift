import AVFoundation
import CoreVideo

/// Detects when a new card is dropped into the scanning station.
///
/// Combines two signals on each camera frame:
/// 1. **YOLO detection** — confirms a card object is visible (not just bin geometry).
/// 2. **Frame differencing** — confirms the scene changed significantly relative to
///    the last captured frame (i.e., a new card was placed, not the same card).
///
/// A "new card" event fires only when both signals agree. After a capture, call
/// `markCaptured()` so the next card drop is measured relative to the new reference.
///
/// When a `detectionZone` is set, detections are filtered to require:
/// - Full containment within the zone
/// - Minimum area coverage (≥40% of frame by default)
/// - Portrait aspect ratio
///
/// Threading: `processFrame(_:)` is safe to call from any queue.  Internal work runs
/// on a dedicated serial queue.  `onNewCardSignal` is always called on the main queue.
final class CardPresenceTracker: @unchecked Sendable {

    // MARK: - Configuration

    /// Minimum frame-difference score (0–1) to count as a meaningful scene change.
    var sceneChangeThreshold: Float = 0.03

    /// Minimum YOLO confidence for a card to be considered present.
    var confidenceThreshold: Float = 0.5 {
        didSet { detector?.confidenceThreshold = confidenceThreshold }
    }

    /// Detection zone for filtering card detections.
    ///
    /// When set, only cards meeting the zone's constraints are accepted:
    /// containment, minimum area, and portrait aspect ratio.
    var detectionZone: DetectionZone? {
        didSet {
            // Clear reference samples when zone changes to ensure sample counts match
            // (samples from full frame have different count than samples from zone)
            referenceSamples = []
        }
    }

    // MARK: - Callbacks

    /// Called on the main queue when a new card is detected.
    ///
    /// The `CGRect?` is the highest-confidence bounding box in normalized top-left-origin
    /// image coordinates, or `nil` if position data is unavailable.
    var onNewCardSignal: ((CGRect?) -> Void)?

    // MARK: - Private

    private let detectorProvider: () -> YOLOCardDetector?
    private let analyzer = FrameDifferenceAnalyzer()
    private let presenceQueue = DispatchQueue(
        label: "com.mtgscanner.cardpresence",
        qos: .userInitiated
    )
    private let processingSemaphore = DispatchSemaphore(value: 1)
    private var detector: YOLOCardDetector?
    private var hasLoadedDetector = false
    private var referenceSamples: [UInt8] = []
    private var lastSamples: [UInt8] = []

    // MARK: - Init

    init(detectorProvider: @escaping () -> YOLOCardDetector? = { nil }) {
        self.detectorProvider = detectorProvider
    }

    convenience init(detector: YOLOCardDetector?) {
        self.init(detectorProvider: { detector })
    }

    // MARK: - Still-Image Detection

    /// Detects the highest-confidence card bounding box in `cgImage` using the shared detector.
    ///
    /// Runs on the presence queue (background) and returns the result asynchronously.
    /// Returns `nil` if no card is detected or the detector is unavailable.
    func detectBestBox(in cgImage: CGImage) async -> CGRect? {
        await withCheckedContinuation { continuation in
            presenceQueue.async { [weak self] in
                guard let self else { continuation.resume(returning: nil); return }
                let boxes = self.loadDetector()?.detect(in: cgImage) ?? []
                let best = boxes.max(by: { $0.confidence < $1.confidence })?.rect
                continuation.resume(returning: best)
            }
        }
    }

    // MARK: - Reference Management

    /// Updates the reference frame to the most recently processed frame.
    ///
    /// Call this immediately after each successful capture so the next card drop
    /// is evaluated relative to the newly captured card's appearance.
    func markCaptured() {
        presenceQueue.async { [weak self] in
            guard let self else { return }
            // Use the same zone for reference samples that we'll use for future samples
            // to ensure sample counts match during comparison
            let motionZone = self.detectionZone?.effectiveRect
            self.referenceSamples = self.lastSamples
            #if DEBUG
            print("[CardPresence] markCaptured - Zone: \(String(describing: motionZone)), " +
                  "Samples: \(self.referenceSamples.count)")
            #endif
        }
    }

    // MARK: - Zone Calibration

    /// Calibrates the detection zone from a captured card's bounding box.
    ///
    /// The zone is set to the detected card's position, allowing future detections
    /// to be filtered to cards in a similar location.
    func calibrate(from boundingBox: CGRect) {
        presenceQueue.async { [weak self] in
            self?.detectionZone = DetectionZone.calibrated(from: boundingBox)
            // Clear reference samples so next frame establishes new reference with zone
            self?.referenceSamples = []
        }
    }

    /// Resets the detection zone to nil (full frame detection).
    func resetZone() {
        presenceQueue.async { [weak self] in
            self?.detectionZone = nil
            // Clear reference samples so next frame establishes new reference without zone
            self?.referenceSamples = []
        }
    }

    // MARK: - Frame Processing

    /// Process a camera frame. Drops the frame if a previous frame is still being processed.
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard processingSemaphore.wait(timeout: .now()) == .success else { return }
        presenceQueue.async { [weak self] in
            guard let self else { return }
            defer { self.processingSemaphore.signal() }
            self.process(pixelBuffer: pixelBuffer)
        }
    }

    private func process(pixelBuffer: CVPixelBuffer) {
        // Get the zone for motion detection (use effectiveRect for the full detection area)
        let motionZone = detectionZone?.effectiveRect

        let samples = analyzer.sample(pixelBuffer, zone: motionZone)
        lastSamples = samples

        #if DEBUG
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        print("[CardPresence] Zone: \(String(describing: motionZone)), " +
              "Buffer: \(width)x\(height), Samples: \(samples.count)")
        print("[CardPresence] Reference samples: \(referenceSamples.count)")
        #endif

        let diff = referenceSamples.isEmpty
            ? 1.0  // no reference yet — always treat as changed
            : analyzer.difference(from: referenceSamples, to: samples)

        #if DEBUG
        print("[CardPresence] Diff: \(diff), Threshold: \(sceneChangeThreshold)")
        #endif

        guard diff >= sceneChangeThreshold else { return }

        let boxes = loadDetector()?.detect(in: pixelBuffer) ?? []

        #if DEBUG
        print("[CardPresence] YOLO boxes: \(boxes.count)")
        #endif

        guard !boxes.isEmpty else { return }

        let bestBox = filterBoxes(boxes)

        #if DEBUG
        print("[CardPresence] Filtered best box: \(String(describing: bestBox))")
        #endif

        DispatchQueue.main.async { [weak self] in
            self?.onNewCardSignal?(bestBox)
        }
    }

    private func filterBoxes(_ boxes: [CardBoundingBox]) -> CGRect? {
        let filtered = boxes.filter { box in
            passesZoneFilter(box.rect)
        }
        return filtered.max(by: { $0.confidence < $1.confidence })?.rect
    }

    private func passesZoneFilter(_ box: CGRect) -> Bool {
        guard let zone = detectionZone else { return true }
        // YOLO returns boxes in top-left origin coordinates
        // Zone uses Vision coordinates (bottom-left origin)
        // Convert YOLO box to Vision coordinates for comparison
        let visionBox = CGRect(
            x: box.minX,
            y: 1.0 - box.maxY,
            width: box.width,
            height: box.height
        )
        return zone.contains(visionBox) && zone.isLargeEnough(visionBox) && zone.isPortraitAspect(visionBox)
    }

    private func loadDetector() -> YOLOCardDetector? {
        if !hasLoadedDetector {
            detector = detectorProvider()
            hasLoadedDetector = true
        }
        detector?.confidenceThreshold = confidenceThreshold
        return detector
    }
}
