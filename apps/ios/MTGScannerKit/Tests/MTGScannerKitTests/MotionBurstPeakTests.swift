import XCTest
@testable import MTGScannerKit

/// Tests for MotionBurstDetector peak threshold functionality.
final class MotionBurstPeakTests: XCTestCase {

    func testShadowWithoutPeakIsRejected() {
        // Simulate shadow: gradual rise to diff that is < 2× the idle baseline.
        // Idle baseline ≈ 0.010 after warmup; shadow peak of 0.015 is only 1.5× — rejected.
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.015,
            maxHoverDuration: 3,  // Short hover to trigger reset quickly
            minPeakThreshold: 0.05  // absolute floor (adaptive threshold = max(0.01, 0.020))
        ))

        // Warm up — establishes idle baseline ≈ 0.010
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        // Gradual rise (shadow pattern) — peak 0.015 < adaptiveThreshold (0.020 = 0.010 * 2)
        _ = detector.process(diff: 0.012)
        _ = detector.process(diff: 0.014)

        // Continue with varying diffs to trigger hover timeout, then flush ring buffer with low diffs
        for i in 0..<12 {
            _ = detector.process(diff: 0.014 + Float(i % 3) * 0.001)
        }
        // Flush ring buffer so re-triggered bursts from residual high diffs clear out
        for _ in 0..<4 {
            _ = detector.process(diff: 0.005)
        }

        // Should NOT have triggered capture — shadow rejected by adaptive peak check
        XCTAssertEqual(detector.state, .idle)
    }

    func testCardWithPeakTriggers() {
        // Simulate card: sharp spike to diff that is ≥ 2× the idle baseline.
        // Idle baseline ≈ 0.010; peak of 0.08 is 8× — accepted.
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.015,
            minPeakThreshold: 0.05  // absolute floor (adaptive = max(0.01, 0.020))
        ))

        // Warm up — establishes idle baseline ≈ 0.010
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        // Sharp spike (card pattern) — peak 0.08 >> adaptiveThreshold (0.020)
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
        // adaptiveThreshold = max(0.010, 0.005 * 2) = max(0.010, 0.010) = 0.010 → accepted.
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.010,  // Lower threshold for dark scene
            minPeakThreshold: 0.05   // Absolute floor — adaptive replaces this
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

        // SHOULD detect — burst peak >= adaptiveThreshold (0.010)
        XCTAssertTrue(triggered)
        XCTAssertEqual(detector.state, .settled)
    }

 func testLightChangeWithoutPeakIsRejected() {
        // Simulate a noisy environment where idle baseline is elevated, then a light
        // change occurs. The light-change peak must be < 2× the idle baseline to be rejected.
        // We use motionThreshold=0.030 so warmup frames at 0.020 stay below threshold.
        // Idle baseline ≈ 0.020; adaptiveThreshold = max(0.010, 0.020 * 2) = max(0.010, 0.040) = 0.040.
        // Peak = 0.035 < 0.040 → rejected.
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

        // Step change (light flicker) — peak 0.035 < adaptiveThreshold (max(0.010, 0.040)=0.040)
        _ = detector.process(diff: 0.030)
        _ = detector.process(diff: 0.032)
        _ = detector.process(diff: 0.035)

        // Continue with varying diffs to trigger hover timeout, then flush ring buffer with low diffs
        for i in 0..<12 {
            _ = detector.process(diff: 0.035 + Float(i % 3) * 0.003)
        }
        // Flush ring buffer so re-triggered bursts from residual high diffs clear out
        for _ in 0..<5 {
            _ = detector.process(diff: 0.005)
        }

        // Should NOT have triggered capture — light change rejected by adaptive peak check
        XCTAssertEqual(detector.state, .idle)
    }

    func testGentleCardPlacementWithLowDiffTriggers() {
        // Simulate a gently placed card with modest diff values.
        // Idle baseline ≈ 0.003; gentle placement peak of 0.012 = 4× baseline — accepted.
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.010,
            minPeakThreshold: 0.05
        ))

        // Warm up — very low ambient noise
        for _ in 0..<4 {
            _ = detector.process(diff: 0.003)
        }

        // Gentle card placement — modest but clear spike
        _ = detector.process(diff: 0.012)
        _ = detector.process(diff: 0.010)

        // Settlement: diffs drop back toward baseline
        _ = detector.process(diff: 0.004)
        let triggered = detector.process(diff: 0.003)

        // SHOULD detect — peak (0.012) >= adaptiveThreshold (max(0.010, 0.006)=0.010)
        XCTAssertTrue(triggered)
        XCTAssertEqual(detector.state, .settled)
    }
}
