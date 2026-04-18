import Foundation

/// Detects card arrival patterns using temporal frame differencing.
///
/// Distinguishes card arrivals (burst of motion followed by settlement) from
/// shadows (step change or sustained drift) by tracking frame-to-frame differences
/// over a sliding window.
///
/// Threading: All methods are safe to call from any queue. Internal state is
/// managed synchronously (no locks needed as long as called from single queue).
struct MotionBurstDetector: Sendable {

    // MARK: - Configuration

    var configuration: MotionBurstConfiguration

    // MARK: - State

    private(set) var state: BurstDetectionState = .idle
    private(set) var frameIndex: Int = 0

    /// Ring buffer of recent diff values.
    private var diffHistory: [Float] = []

    /// Consecutive frames below threshold (for settlement detection).
    private var consecutiveLowFrames: Int = 0

    /// Consecutive frames with stable diff (for settlement detection when card is in frame).
    private var consecutiveStableFrames: Int = 0

    /// Previous diff value for stability calculation.
    private var previousDiff: Float = 0

    /// Frame index when current burst/hover started.
    private var burstStartFrame: Int?

    /// Maximum diff observed during current burst (for peak detection).
    private var burstMaxDiff: Float = 0

    /// Exponential moving average of idle diff values (ambient noise baseline).
    private var idleBaseline: Float = 0

    /// Timestamp of last reference frame update.
    internal(set) var lastReferenceUpdate: Date = Date()

    // MARK: - Metrics (for debug overlay)

    struct Metrics: Sendable {
        let currentDiff: Float
        let recentDiffs: [Float]
        let state: BurstDetectionState
        let consecutiveLowFrames: Int
        let framesSinceBurstStart: Int?
        let rejectionReason: String?
        let shouldUpdateReference: Bool
        let idleBaseline: Float
    }

    private(set) var lastRejectionReason: String?

    /// Set to true when reference frame should be updated (e.g., after hover reset).
    private(set) var shouldUpdateReference: Bool = false

    // MARK: - Init

    init(configuration: MotionBurstConfiguration = .balanced) {
        self.configuration = configuration
        self.diffHistory = Array(repeating: 0.0, count: configuration.burstWindowSize)
    }

    // MARK: - Detection

    /// Processes a new frame diff and updates state machine.
    ///
    /// - Parameter diff: Normalized frame difference (0-1) from previous frame.
    /// - Returns: `true` if settlement is confirmed (ready to capture), `false` otherwise.
    @discardableResult
    mutating func process(diff: Float) -> Bool {
        // Update history buffer
        diffHistory[frameIndex % configuration.burstWindowSize] = diff
        frameIndex += 1

        // Update consecutive low frame counter
        if diff < configuration.motionThreshold {
            consecutiveLowFrames += 1
        } else {
            consecutiveLowFrames = 0
        }

        // Update consecutive stable frame counter (diff not changing much = card settled)
        let diffDelta = abs(diff - previousDiff)
        if diffDelta < configuration.motionThreshold * 0.5 {
            consecutiveStableFrames += 1
        } else {
            consecutiveStableFrames = 0
        }
        previousDiff = diff

        // Track max diff during active states
        if state.isActive {
            burstMaxDiff = max(burstMaxDiff, diff)
        }

        // State machine transitions
        switch state {
        case .idle:
            handleIdleState(diff: diff)
        case .burstDetected(let startFrame):
            handleBurstDetectedState(diff: diff, startFrame: startFrame)
        case .hovering(let startFrame):
            handleHoveringState(diff: diff, startFrame: startFrame)
        case .settled:
            // Should not stay in settled; caller should reset after capture
            state = .idle
            return false
        }

        return state == .settled
    }

    /// Checks if reference frame should be decayed (shadow baseline drift).
    ///
    /// Call periodically (e.g., every frame or every N frames).
    /// - Returns: `true` if reference should be updated to current frame.
    mutating func shouldDecayReference() -> Bool {
        let elapsed = Date().timeIntervalSince(lastReferenceUpdate)
        guard elapsed > configuration.referenceDecayTimeout else { return false }

        // Only decay if not in active motion state
        guard !state.isActive else { return false }

        lastReferenceUpdate = Date()
        return true
    }

    /// Updates the reference timestamp (call when reference frame is updated).
    mutating func markReferenceUpdated() {
        lastReferenceUpdate = Date()
        shouldUpdateReference = false
    }

    /// Resets state machine to idle.
    mutating func reset() {
        state = .idle
        frameIndex = 0
        diffHistory = Array(repeating: 0.0, count: configuration.burstWindowSize)
        consecutiveLowFrames = 0
        consecutiveStableFrames = 0
        previousDiff = 0
        burstStartFrame = nil
        burstMaxDiff = 0
        lastRejectionReason = nil
        shouldUpdateReference = true
    }

    /// Returns current metrics for debug overlay.
    func currentMetrics() -> Metrics {
        let framesSinceBurst: Int? = burstStartFrame.map { frameIndex - $0 }
        let lastDiffIndex = frameIndex == 0 ? 0 : (frameIndex - 1) % configuration.burstWindowSize
        return Metrics(
            currentDiff: diffHistory[lastDiffIndex],
            recentDiffs: orderedRecentDiffs(count: configuration.burstWindowSize),
            state: state,
            consecutiveLowFrames: consecutiveLowFrames,
            framesSinceBurstStart: framesSinceBurst,
            rejectionReason: lastRejectionReason,
            shouldUpdateReference: shouldUpdateReference,
            idleBaseline: idleBaseline
        )
    }

    // MARK: - Private State Handlers

    private mutating func handleIdleState(diff: Float) {
        lastRejectionReason = nil

        // Update idle baseline EMA with low-motion frames only.
        // Excluding above-threshold frames prevents card arrival frames (which are
        // processed in idle before burst is detected) from inflating the baseline.
        if diff < configuration.motionThreshold {
            idleBaseline = idleBaseline == 0 ? diff : idleBaseline * 0.95 + diff * 0.05
        }

        guard frameIndex >= configuration.burstWindowSize else {
            lastRejectionReason = "Warming up (\(frameIndex)/\(configuration.burstWindowSize))"
            return
        }

        let burstCount = countRecentFramesAboveThreshold()
        guard burstCount >= configuration.burstFrameCount else {
            lastRejectionReason = "No burst: \(burstCount)/\(configuration.burstFrameCount) frames above threshold"
            return
        }

        // Burst detected
        state = .burstDetected(burstStartFrame: frameIndex)
        burstStartFrame = frameIndex
        burstMaxDiff = diff
        consecutiveLowFrames = 0
    }

    private mutating func handleBurstDetectedState(diff: Float, startFrame: Int) {
        let elapsedFrames = frameIndex - startFrame

        // Check for settlement (low diff OR stable diff)
        // Low diff = card moved through frame
        // Stable diff = card stopped moving in frame
        let settled = consecutiveLowFrames >= configuration.settlementFrames ||
                     consecutiveStableFrames >= configuration.settlementFrames
        if settled {
            // Require the burst peak to be a meaningful spike above ambient noise.
            // Use 3× the idle baseline so detection adapts to ambient lighting:
            // dark scenes produce compressed diffs, but a card arrival still creates
            // a spike several times larger than the noise floor.
            // The absolute floor (minPeakThreshold / 5) is a sanity minimum only —
            // the ratio check is the primary discriminator.
            let adaptiveThreshold = max(configuration.minPeakThreshold / 5.0, idleBaseline * 3.0)
            guard burstMaxDiff >= adaptiveThreshold else {
                let maxStr = String(format: "%.3f", burstMaxDiff)
                let threshStr = String(format: "%.3f", adaptiveThreshold)
                let baseStr = String(format: "%.3f", idleBaseline)
                lastRejectionReason = "No sharp peak: \(maxStr) < \(threshStr) (baseline=\(baseStr))"
                reset()
                return
            }
            state = .settled
            return
        }

        // Check for hover timeout
        if elapsedFrames > configuration.maxHoverDuration {
            state = .hovering(burstStartFrame: startFrame)
            lastRejectionReason = "Hover timeout (\(elapsedFrames) frames)"
            return
        }

        // Still in burst - check if motion stopped without settlement
        if diff < configuration.motionThreshold && consecutiveLowFrames > 1 {
            // Hand/object removed without card settlement
            if elapsedFrames < configuration.settlementFrames {
                reset()
                lastRejectionReason = "Motion stopped without settlement"
            }
        }
    }

    private mutating func handleHoveringState(diff: Float, startFrame: Int) {
        let elapsedFrames = frameIndex - startFrame

        // Check for settlement (low diff OR stable diff)
        let settled = consecutiveLowFrames >= configuration.settlementFrames * 2 ||
                     consecutiveStableFrames >= configuration.settlementFrames
        if settled {
            state = .settled
            return
        }

        // Force reset after extended hover - shadow has become new baseline
        if elapsedFrames > configuration.maxHoverDuration * 3 {
            reset()
            lastRejectionReason = "Hover baseline reset"
            return
        }

        // If motion has completely stopped, reset
        if consecutiveLowFrames > configuration.maxHoverDuration {
            reset()
            lastRejectionReason = "Hover ended without capture"
        }
    }

    // MARK: - Helpers

    /// Returns the most recent `count` diff values in chronological order.
    private func orderedRecentDiffs(count: Int) -> [Float] {
        let actualCount = min(count, frameIndex)
        guard actualCount > 0 else { return [] }
        var result = [Float](repeating: 0.0, count: actualCount)
        for i in 0..<actualCount {
            let idx = (frameIndex - actualCount + i) % configuration.burstWindowSize
            result[i] = diffHistory[idx]
        }
        return result
    }

    /// Counts frames above threshold in the recent window.
    private func countRecentFramesAboveThreshold() -> Int {
        var count = 0
        let windowStart = max(0, frameIndex - configuration.burstWindowSize)
        let windowEnd = frameIndex

        for i in windowStart..<windowEnd {
            let idx = i % configuration.burstWindowSize
            if diffHistory[idx] >= configuration.motionThreshold {
                count += 1
            }
        }

        return count
    }
}
