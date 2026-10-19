import AVFoundation
import CoreVideo

/// Detects when a new card is dropped into the scanning station.
///
/// Combines two signals on each camera frame:
/// 1. **YOLO detection** — confirms a card object is visible (not just bin geometry).
/// 2. **Motion burst detection** — confirms the scene changed with the characteristic
///    "burst then settle" pattern of a card sliding into the bin (not shadows).
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

    /// Motion burst detection configuration.
    ///
    /// Controls sensitivity for detecting card arrivals vs rejecting shadows.
    /// Use `.balanced`, `.fast`, or `.conservative` presets, or customize individually.
    var burstConfiguration: MotionBurstConfiguration {
        didSet {
            let newDetector = MotionBurstDetector(configuration: burstConfiguration)
            presenceQueue.async { [weak self] in
                guard let self else { return }
                burstDetector = newDetector
                sceneReference = SceneMotionReference(
                    windowSize: newDetector.configuration.burstWindowSize,
                    startupMotionThreshold: newDetector.configuration.minPeakThreshold
                )
                publishReadiness()
            }
        }
    }

    /// Minimum YOLO confidence for a card to be considered present.
    var confidenceThreshold: Float = 0.5 {
        didSet {
            let threshold = confidenceThreshold
            presenceQueue.async { [weak self] in
                self?.detector?.confidenceThreshold = threshold
            }
        }
    }

    /// Detection zone for filtering card detections.
    ///
    /// When set, only cards meeting the zone's constraints are accepted:
    /// containment, minimum area, and portrait aspect ratio.
    ///
    /// Always mutate via `setZone(_:)` or `markCapturedAndSetZone(_:)` —
    /// never assign directly, as those methods dispatch to the presenceQueue.
    private(set) var detectionZone: DetectionZone?

    /// Whether to enable legacy single-threshold mode (for debugging).
    /// When true, ignores motion burst detection and uses simple threshold.
    var useLegacyDetection: Bool = false

    /// Legacy threshold for single-frame detection (deprecated, use burstConfiguration).
    @available(*, deprecated, message: "Use burstConfiguration.motionThreshold instead")
    var sceneChangeThreshold: Float {
        get { burstConfiguration.motionThreshold }
        set { burstConfiguration.motionThreshold = newValue }
    }

    // MARK: - Callbacks

    /// Called on the main queue when a new card is detected.
    ///
    /// The `CGRect?` is the highest-confidence bounding box in normalized top-left-origin
    /// image coordinates, or `nil` if position data is unavailable.
    var onReadinessChanged: (@MainActor @Sendable (Bool, UUID) -> Void)?

    var onNewCardSignal: (@Sendable (CGRect?, UUID) -> Void)?

    /// Called on the main queue with updated detection metrics for debug overlay.
    /// Only called when debug mode is enabled.
    var onDebugMetrics: ((MotionBurstDetector.Metrics) -> Void)?

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
    private var sceneReference = SceneMotionReference(windowSize: 8)
    private var publishedReadiness = false
    private var sampledSize = CGSize.zero
    private var sampledZone: CGRect?
    private var motionIndices: [Int] = []
    private var lastSamples: [UInt8] = []
    private var burstDetector: MotionBurstDetector
    private var debugMode: Bool = false
    /// True after a successful card signal, until `markCaptured()` is called.
    /// Prevents the burst detector from re-triggering on the same card before
    /// the VM has acknowledged the capture.
    private var pendingCapture: Bool = false
    private var sessionID = UUID()
    private let detectCards: (@Sendable (CVPixelBuffer) -> [CardBoundingBox])?

    // MARK: - Init

    init(
        detectorProvider: @escaping () -> YOLOCardDetector? = { nil },
        burstConfiguration: MotionBurstConfiguration = .balanced,
        detectCards: (@Sendable (CVPixelBuffer) -> [CardBoundingBox])? = nil
    ) {
        self.detectorProvider = detectorProvider
        self.detectCards = detectCards
        self.burstConfiguration = burstConfiguration
        self.burstDetector = MotionBurstDetector(configuration: burstConfiguration)
        self.sceneReference = SceneMotionReference(
            windowSize: burstConfiguration.burstWindowSize, startupMotionThreshold: burstConfiguration.minPeakThreshold
        )
    }

    convenience init(
        detector: YOLOCardDetector?,
        burstConfiguration: MotionBurstConfiguration = .balanced
    ) {
        self.init(detectorProvider: { detector }, burstConfiguration: burstConfiguration)
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

    /// Clears all session state, even when the detection zone is already nil.
    func resetSession(_ sessionID: UUID) {
        presenceQueue.async { [weak self] in
            guard let self else { return }
            self.sessionID = sessionID
            self.detectionZone = nil
            self.referenceSamples = []
            self.lastSamples = []
            self.sceneReference = SceneMotionReference(
                windowSize: self.burstConfiguration.burstWindowSize,
                startupMotionThreshold: self.burstConfiguration.minPeakThreshold
            )
            self.publishReadiness()
            self.burstDetector.reset()
            self.pendingCapture = false
        }
    }

    /// Updates the reference frame to the most recently processed frame.
    ///
    /// Call this immediately after each successful capture so the next card drop
    /// is evaluated relative to the newly captured card's appearance.
    func markCaptured() {
        presenceQueue.async { [weak self] in
            guard let self else { return }
            self.applyMarkCaptured()
        }
    }

    /// Atomically marks capture and sets a new detection zone on the presenceQueue.
    ///
    /// Use instead of calling `markCaptured()` followed by `setZone(_:)` to guarantee
    /// the zone change never races with or undoes the reference update.
    func markCapturedAndSetZone(_ zone: DetectionZone) {
        presenceQueue.async { [weak self] in
            guard let self else { return }
            self.detectionZone = zone
            self.updateMotionIndices(size: self.sampledSize)
            self.applyMarkCaptured()
        }
    }

    /// Waits for preceding reset/rearm operations on the serial tracker queue.
    func finishRearming() async {
        await withCheckedContinuation { continuation in
            presenceQueue.async { continuation.resume() }
        }
    }

    /// Sets the detection zone while retaining the fixed full-frame sample grid.
    ///
    /// Dispatches to the presenceQueue so it serialises with frame processing.
    /// No-ops if the zone is already equal to the requested value (idempotent).
    func setZone(_ zone: DetectionZone?) {
        presenceQueue.async { [weak self] in
            guard let self else { return }
            guard self.detectionZone != zone else { return }
            self.detectionZone = zone
        }
    }

    private func applyMarkCaptured() {
        referenceSamples = lastSamples
        sceneReference.rearm(motionThreshold: burstConfiguration.motionThreshold, within: motionIndices)
        burstDetector.reset()
        burstDetector.markReferenceUpdated()
        pendingCapture = false
        publishReadiness()
        #if DEBUG
        print("\(logTimestamp()) [CardPresence] markCaptured - ready=\(sceneReference.isReady)")
        #endif
    }

    /// Enables or disables debug mode for metrics collection.
    func setDebugMode(_ enabled: Bool) {
        presenceQueue.async { [weak self] in
            self?.debugMode = enabled
        }
    }

    // MARK: - Zone Calibration

    /// Calibrates the detection zone from a captured card's bounding box.
    ///
    /// The zone is set to the detected card's position, allowing future detections
    /// to be filtered to cards in a similar location.
    func calibrate(from boundingBox: CGRect) {
        setZone(DetectionZone.calibrated(from: boundingBox))
    }

    /// Resets the detection zone to nil (full frame detection).
    func resetZone() {
        setZone(nil)
    }

    // MARK: - Frame Processing

    /// Process a camera frame. Drops the frame if a previous frame is still being processed.
    func processFrame(_ sampleBuffer: CMSampleBuffer, allowCapture: Bool = true) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard processingSemaphore.wait(timeout: .now()) == .success else {
            #if DEBUG
            if FrameDifferenceAnalyzer.profilesSampling { print("[StationSample] dropped busy frame") }
            #endif
            return
        }
        presenceQueue.async { [weak self] in
            guard let self else { return }
            defer { self.processingSemaphore.signal() }
            self.process(pixelBuffer: pixelBuffer, allowCapture: allowCapture)
        }
    }

    private func process(pixelBuffer: CVPixelBuffer, allowCapture: Bool) {
        // A fixed full-frame grid keeps learned noise valid when the YOLO acceptance zone changes.
        updateMotionIndices(pixelBuffer)
        let samples = analyzer.sample(pixelBuffer)
        lastSamples = samples
        let change = sceneReference.observe(samples, within: motionIndices)
        publishReadiness()
        guard allowCapture, !pendingCapture else { return }
        let legacyMode = useLegacyDetection
        let diff = legacyMode ? analyzer.difference(from: referenceSamples, to: samples) : change.motion
        if referenceSamples.isEmpty { referenceSamples = samples }
        let shouldTrigger = legacyMode ? diff >= burstConfiguration.motionThreshold :
            burstDetector.process(diff: diff, isFrameStable: change.adjacent < burstConfiguration.motionThreshold)
        if burstDetector.currentMetrics().shouldUpdateReference ||
            (diff < burstConfiguration.motionThreshold && burstDetector.shouldDecayReference()) {
            sceneReference.recenter()
            burstDetector.markReferenceUpdated()
        }
        sendDebugMetricsIfEnabled()
        #if DEBUG
        logDetectionState(diff: diff, shouldTrigger: shouldTrigger)
        #endif
        guard sceneReference.isReady, shouldTrigger else { return }
        processTriggeredFrame(pixelBuffer: pixelBuffer)
    }

    private func updateMotionIndices(_ buffer: CVPixelBuffer) {
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        updateMotionIndices(size: size)
    }

    private func updateMotionIndices(size: CGSize) {
        let zone = detectionZone?.effectiveRect
        guard size != sampledSize || zone != sampledZone else { return }
        sampledSize = size
        sampledZone = zone
        motionIndices = analyzer.sampleIndices(width: Int(size.width), height: Int(size.height), zone: zone)
    }

    private func publishReadiness() {
        let ready = sceneReference.isReady
        guard ready != publishedReadiness else { return }
        publishedReadiness = ready
        let generation = sessionID
        DispatchQueue.main.async { [weak self] in self?.onReadinessChanged?(ready, generation) }
    }

    private func sendDebugMetricsIfEnabled() {
        guard debugMode else { return }
        let metrics = burstDetector.currentMetrics()
        DispatchQueue.main.async { [weak self] in
            self?.onDebugMetrics?(metrics)
        }
    }

    private func resetDetectionState() {
        sceneReference.recenter()
        referenceSamples = lastSamples
        burstDetector.reset()
        burstDetector.markReferenceUpdated()
    }

    private func processTriggeredFrame(pixelBuffer: CVPixelBuffer) {
        guard let bestBox = detectBestFilteredBox(in: pixelBuffer) else { return }
        pendingCapture = true
        sceneReference.beginCapture()
        resetDetectionState()
        let signalSessionID = sessionID
        DispatchQueue.main.async { [weak self] in
            self?.onNewCardSignal?(bestBox, signalSessionID)
        }
    }

    private func detectBestFilteredBox(in pixelBuffer: CVPixelBuffer) -> CGRect? {
        let boxes = detectCards?(pixelBuffer) ?? loadDetector()?.detect(in: pixelBuffer) ?? []
        #if DEBUG
        print("\(logTimestamp()) [CardPresence] YOLO boxes: \(boxes.count)")
        #endif
        guard !boxes.isEmpty else {
            resetDetectionState()
            #if DEBUG
            print("\(logTimestamp()) [CardPresence] No YOLO boxes, updated reference to prevent re-trigger")
            #endif
            return nil
        }
        guard let bestBox = filterBoxes(boxes) else {
            resetDetectionState()
            #if DEBUG
            print("\(logTimestamp()) [CardPresence] All \(boxes.count) boxes filtered out by zone constraints")
            #endif
            return nil
        }
        #if DEBUG
        print("\(logTimestamp()) [CardPresence] Filtered best box: \(bestBox)")
        #endif
        return bestBox
    }

}

// MARK: - Debug Logging
#if DEBUG
private extension CardPresenceTracker {
    var logDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }

    func logTimestamp() -> String {
        "[\(logDateFormatter.string(from: Date()))]"
    }

    func logFrameInfo(pixelBuffer: CVPixelBuffer, samples: [UInt8], motionZone: CGRect?) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        print("\(logTimestamp()) [CardPresence] Zone: \(String(describing: motionZone)), " +
              "Buffer: \(width)x\(height), Samples: \(samples.count)")
        print("\(logTimestamp()) [CardPresence] Reference samples: \(referenceSamples.count)")
    }

    func logDetectionState(diff: Float, shouldTrigger: Bool) {
        let metrics = burstDetector.currentMetrics()
        print("\(logTimestamp()) [CardPresence] Diff: \(diff), State: \(metrics.state.displayName), " +
              "Trigger: \(shouldTrigger)")
        if let reason = metrics.rejectionReason {
            print("\(logTimestamp()) [CardPresence] Rejection: \(reason)")
        }
    }
}
#endif

// MARK: - Box Filtering
private extension CardPresenceTracker {
    func filterBoxes(_ boxes: [CardBoundingBox]) -> CGRect? {
        let filtered = boxes.filter { box in
            passesZoneFilter(box.rect)
        }
        return filtered.max(by: { $0.confidence < $1.confidence })?.rect
    }

   func passesZoneFilter(_ box: CGRect) -> Bool {
        let zone = detectionZone ?? .uncalibrated
        // YOLO returns boxes in top-left origin coordinates
        // Zone uses Vision coordinates (bottom-left origin)
        // Convert YOLO box to Vision coordinates for comparison
        let visionBox = CGRect(
            x: box.minX,
            y: 1.0 - box.maxY,
            width: box.width,
            height: box.height
        )
        // Use center-proximity for calibrated zones (allows cards slightly offset
        // from calibration position) and strict containment for uncalibrated zones.
        let inZone: Bool
        if detectionZone != nil {
            inZone = zone.containsCenter(of: visionBox)
        } else {
            inZone = zone.contains(visionBox)
        }
        let largeEnough = zone.isLargeEnough(visionBox)
        let portrait = zone.isPortraitAspect(visionBox)
        #if DEBUG
        if !inZone || !largeEnough || !portrait {
            print("\(logTimestamp()) [CardPresence] Box rejected: yolo=\(box) vision=\(visionBox) " +
                  "zone=\(zone.effectiveRect) inZone=\(inZone) " +
                  "largeEnough=\(largeEnough) portrait=\(portrait)")
        }
        #endif
        return inZone && largeEnough && portrait
    }

    func loadDetector() -> YOLOCardDetector? {
        if !hasLoadedDetector {
            detector = detectorProvider()
            hasLoadedDetector = true
        }
        detector?.confidenceThreshold = confidenceThreshold
        return detector
    }
}
