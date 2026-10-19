import Foundation

/// Learns sampled luminance variation during existing warmup and capture work.
/// All state belongs to CardPresenceTracker's serial queue; no timers or Vision requests.
struct SceneMotionReference {
    struct Change {
        let motion: Float
        let adjacent: Float
    }

    let windowSize: Int
    private let startupMotionThreshold: Float
    private(set) var isReady = false
    private var lower: [UInt8] = []
    private var upper: [UInt8] = []
    private var previous: [UInt8] = []
    private var recent: [[UInt8]] = []
    private var learnedFrames = 0
    private var activeIndices: [Int]?

    init(windowSize: Int, startupMotionThreshold: Float = 0.05) {
        self.windowSize = windowSize
        self.startupMotionThreshold = startupMotionThreshold
    }

    mutating func observe(_ samples: [UInt8], within indices: [Int]? = nil) -> Change {
        guard !samples.isEmpty else { return Change(motion: 0, adjacent: 1) }
        if lower.count != samples.count {
            self = Self(windowSize: windowSize, startupMotionThreshold: startupMotionThreshold)
        }
        activeIndices = indices
        recent.append(samples)
        if recent.count > windowSize { recent.removeFirst() }
        defer { previous = samples }
        guard isReady else {
            learn(samples)
            return Change(motion: 0, adjacent: 0)
        }
        var motion = 0, adjacent = 0
        let measuredIndices = indices ?? Array(samples.indices)
        for index in measuredIndices {
            let value = Int(samples[index])
            motion += max(Int(lower[index]) - value, value - Int(upper[index]), 0)
            let width = Int(upper[index]) - Int(lower[index])
            adjacent += max(abs(value - Int(previous[index])) - width, 0)
        }
        let normalization = Float(max(measuredIndices.count, 1) * 255)
        return Change(motion: Float(motion) / normalization, adjacent: Float(adjacent) / normalization)
    }

    /// Sampling continues during settling/photo/crop, so the new baseline is already available at acknowledgement.
    mutating func beginCapture() { recent.removeAll(keepingCapacity: true) }

    mutating func rearm(motionThreshold: Float = 0.01, within indices: [Int]? = nil) {
        if let indices { activeIndices = indices }
        guard recent.count >= windowSize else { recenter(); return }
        let wasReady = isReady
        let oldLower = lower, oldUpper = upper
        let previousVariation = variation
        lower = []
        upper = []
        for samples in recent { include(samples) }
        // A quiet band can span both signs of sub-threshold variation. Real movement
        // during preparation must not become an unlimited allowance for future arrivals.
        let limit = max(previousVariation, motionThreshold * 2)
        preserveWidths(from: oldLower, and: oldUpper)
        if wasReady, variation > limit {
            lower = oldLower
            upper = oldUpper
            recenter()
        }
        learnedFrames = recent.count
        isReady = wasReady || learnedFrames >= windowSize
    }

    mutating func recenter() {
        guard previous.count == lower.count else { return }
        for index in previous.indices {
            let width = Int(upper[index]) - Int(lower[index])
            lower[index] = UInt8(clamping: Int(previous[index]) - width / 2)
            upper[index] = UInt8(clamping: Int(previous[index]) + width - width / 2)
        }
    }

    private var variation: Float {
        guard !lower.isEmpty else { return 0 }
        let indices = activeIndices ?? Array(lower.indices)
        let total = indices.reduce(0) { $0 + Int(upper[$1]) - Int(lower[$1]) }
        return Float(total) / Float(max(indices.count, 1) * 255)
    }

    private mutating func learn(_ samples: [UInt8]) {
        let jump = previous.isEmpty ? 0 : samples.indices.reduce(0) {
            $0 + abs(Int(samples[$1]) - Int(previous[$1]))
        }
        include(samples)
        if Float(jump) / Float(samples.count * 255) > startupMotionThreshold ||
            variation > startupMotionThreshold * 2 {
            // Start's touch or a card crossing the warmup window must not become unlimited noise.
            lower = samples
            upper = samples
            recent = [samples]
            learnedFrames = 0
        }
        learnedFrames += 1
        isReady = learnedFrames >= windowSize
    }

    private mutating func preserveWidths(from oldLower: [UInt8], and oldUpper: [UInt8]) {
        guard oldLower.count == lower.count else { return }
        for index in lower.indices {
            let width = max(Int(upper[index]) - Int(lower[index]), Int(oldUpper[index]) - Int(oldLower[index]))
            let center = (Int(lower[index]) + Int(upper[index])) / 2
            lower[index] = UInt8(clamping: center - width / 2)
            upper[index] = UInt8(clamping: center + width - width / 2)
        }
    }

    private mutating func include(_ samples: [UInt8]) {
        guard !lower.isEmpty else { lower = samples; upper = samples; return }
        for index in samples.indices {
            lower[index] = min(lower[index], samples[index])
            upper[index] = max(upper[index], samples[index])
        }
    }
}
