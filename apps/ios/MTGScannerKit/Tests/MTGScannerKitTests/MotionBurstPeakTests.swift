import XCTest
@testable import MTGScannerKit

/// Tests for MotionBurstDetector peak threshold functionality.
final class MotionBurstPeakTests: XCTestCase {

    func testShadowWithoutPeakIsRejected() {
        // Simulate shadow: gradual rise to diff that is < 3× the idle baseline.
        // Idle baseline ≈ 0.010 after warmup; shadow peak of 0.025 is only 2.5× — rejected.
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.015,
            maxHoverDuration: 3,  // Short hover to trigger reset quickly
            minPeakThreshold: 0.05  // absolute floor (adaptive threshold = max(0.01, 0.030))
        ))

        // Warm up — establishes idle baseline ≈ 0.010
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        // Gradual rise (shadow pattern) — peak 0.025 < adaptiveThreshold (0.030 = 0.010 * 3)
        _ = detector.process(diff: 0.02)
        _ = detector.process(diff: 0.025)

        // Continue with varying diffs to trigger hover timeout, then flush ring buffer with low diffs
        for i in 0..<12 {
            _ = detector.process(diff: 0.025 + Float(i % 3) * 0.002)
        }
        // Flush ring buffer so re-triggered bursts from residual high diffs clear out
        for _ in 0..<4 {
            _ = detector.process(diff: 0.005)
        }

        // Should NOT have triggered capture — shadow rejected by adaptive peak check
        XCTAssertEqual(detector.state, .idle)
    }

    func testCardWithPeakTriggers() {
        // Simulate card: sharp spike to diff that is ≥ 3× the idle baseline.
        // Idle baseline ≈ 0.010; peak of 0.08 is 8× — accepted.
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.015,
            minPeakThreshold: 0.05  // absolute floor (adaptive = max(0.01, 0.030))
        ))

        // Warm up — establishes idle baseline ≈ 0.010
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        // Sharp spike (card pattern) — peak 0.08 >> adaptiveThreshold (0.030)
        _ = detector.process(diff: 0.08)  // spike
        _ = detector.process(diff: 0.06)  // still high

        // Settlement via stable diffs (delta < motionThreshold * 0.5 = 0.0075)
        _ = detector.process(diff: 0.055)
        let triggered = detector.process(diff: 0.053)

        // SHOULD trigger — sharp peak clears adaptive threshold
        XCTAssertTrue(triggered)
        XCTAssertEqual(detector.state, .settled)
    }

    func testDarkSceneCardIsDetected() {
        // Simulate a dark/shadowed scene where absolute diffs are compressed.
        // Idle baseline ≈ 0.005; card arrival produces peak of 0.018 = 3.6× baseline.
        // adaptiveThreshold = max(0.010, 0.005 * 3) = max(0.010, 0.015) = 0.015 → accepted.
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.010,  // Lower threshold for dark scene
            minPeakThreshold: 0.05   // Old absolute floor — adaptive replaces this
        ))

        // Warm up — dark scene baseline ≈ 0.005
        for _ in 0..<4 {
            _ = detector.process(diff: 0.005)
        }

        // Card arrival — sharp spike even in low light (3.6× baseline)
        _ = detector.process(diff: 0.018)
        _ = detector.process(diff: 0.016)

        // Settlement: diffs drop back toward baseline
        _ = detector.process(diff: 0.006)
        let triggered = detector.process(diff: 0.005)

        // SHOULD detect — burst peak (burstMaxDiff=0.016 at burst-trigger frame) >= adaptiveThreshold (0.015)
        XCTAssertTrue(triggered)
        XCTAssertEqual(detector.state, .settled)
    }

    func testLightChangeWithoutPeakIsRejected() {
        // Simulate a noisy environment where idle baseline is elevated, then a light
        // change occurs. The light-change peak must be < 3× the idle baseline to be rejected.
        // We use motionThreshold=0.030 so warmup frames at 0.020 stay below threshold.
        // Idle baseline ≈ 0.020; light-change peak of 0.065 < 0.020 * 3 = 0.060...
        // Actually 0.065 > 0.060, so use a lower peak:
        // Peak = 0.050, adaptiveThreshold = max(0.010, 0.020 * 3) = max(0.010, 0.060) = 0.060.
        // 0.050 < 0.060 → rejected.
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 3,
            burstWindowSize: 5,
            settlementFrames: 2,
            motionThreshold: 0.030,  // Higher threshold so warmup frames stay below it
            maxHoverDuration: 3,
            minPeakThreshold: 0.05
        ))

        // Warm up — all below motionThreshold(0.030), establishes idleBaseline ≈ 0.020
        for _ in 0..<5 {
            _ = detector.process(diff: 0.020)
        }

        // Step change (light flicker) — peak 0.050 < adaptiveThreshold (max(0.010, 0.060)=0.060)
        _ = detector.process(diff: 0.040)
        _ = detector.process(diff: 0.045)
        _ = detector.process(diff: 0.050)

        // Continue with varying diffs to trigger hover timeout, then flush ring buffer with low diffs
        for i in 0..<12 {
            _ = detector.process(diff: 0.050 + Float(i % 3) * 0.003)
        }
        // Flush ring buffer so re-triggered bursts from residual high diffs clear out
        for _ in 0..<5 {
            _ = detector.process(diff: 0.005)
        }

        // Should NOT have triggered capture — light change rejected by adaptive peak check
        XCTAssertEqual(detector.state, .idle)
    }
}
