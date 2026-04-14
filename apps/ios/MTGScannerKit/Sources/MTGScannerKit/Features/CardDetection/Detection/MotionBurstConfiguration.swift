import Foundation

/// Configuration for motion burst detection behavior.
///
/// These parameters control how strictly the detector distinguishes
/// card arrivals (characteristic burst-then-settle pattern) from shadows.
struct MotionBurstConfiguration: Sendable, Equatable {
    /// Frames required above threshold to detect a motion burst.
    /// Higher values require more sustained motion, reducing false positives.
    /// Range: 2-8
    var burstFrameCount: Int

    /// Total frames in the evaluation window for burst detection.
    /// Must be greater than burstFrameCount.
    /// Range: 4-12
    var burstWindowSize: Int

    /// Consecutive frames below threshold to confirm settlement.
    /// Higher values add latency but ensure card is truly at rest.
    /// Range: 2-6
    var settlementFrames: Int

    /// Frame difference threshold (0-1) for motion detection.
    /// Higher values require more dramatic change to trigger.
    /// Range: 0.01-0.10
    var motionThreshold: Float

    /// Seconds before reference frame auto-updates to current frame.
    /// Prevents sustained shadows from permanently elevating baseline.
    /// Range: 2-10
    var referenceDecayTimeout: TimeInterval

    /// Maximum frames in burst state without settlement before resetting.
    /// Prevents indefinite hover state when hand/object lingers in frame.
    /// Range: 5-20
    var maxHoverDuration: Int

    /// Minimum peak diff required to qualify as a "sharp" burst.
    /// Shadows and gradual light changes don't have sharp peaks.
    /// Range: 0.03-0.20
    var minPeakThreshold: Float

    init(
        burstFrameCount: Int = 3,
        burstWindowSize: Int = 5,
        settlementFrames: Int = 2,
        motionThreshold: Float = 0.015,
        referenceDecayTimeout: TimeInterval = 5.0,
        maxHoverDuration: Int = 10,
        minPeakThreshold: Float = 0.05
    ) {
        self.burstFrameCount = max(2, min(8, burstFrameCount))
        self.burstWindowSize = max(4, min(12, burstWindowSize))
        self.settlementFrames = max(2, min(6, settlementFrames))
        self.motionThreshold = max(0.01, min(0.10, motionThreshold))
        self.referenceDecayTimeout = max(2.0, min(10.0, referenceDecayTimeout))
        self.maxHoverDuration = max(5, min(20, maxHoverDuration))
        self.minPeakThreshold = max(0.03, min(0.20, minPeakThreshold))
    }

    /// Balanced preset - works for most fixture setups.
    static let balanced = MotionBurstConfiguration()

    /// Fast preset - aggressive detection for quick scanning.
    static let fast = MotionBurstConfiguration(
        burstFrameCount: 2,
        burstWindowSize: 4,
        settlementFrames: 2,
        motionThreshold: 0.02,
        referenceDecayTimeout: 5.0,
        maxHoverDuration: 10,
        minPeakThreshold: 0.04
    )

    /// Conservative preset - strict rejection of shadows.
    static let conservative = MotionBurstConfiguration(
        burstFrameCount: 4,
        burstWindowSize: 6,
        settlementFrames: 3,
        motionThreshold: 0.01,
        referenceDecayTimeout: 5.0,
        maxHoverDuration: 15,
        minPeakThreshold: 0.08
    )
}

extension MotionBurstConfiguration {
    /// Validates that configuration values are internally consistent.
    /// Adjusts burstWindowSize if it's smaller than burstFrameCount.
    mutating func validate() {
        if burstWindowSize < burstFrameCount + 2 {
            burstWindowSize = burstFrameCount + 2
        }
    }
}
