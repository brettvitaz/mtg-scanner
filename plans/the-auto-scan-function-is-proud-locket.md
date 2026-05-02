# Fix Auto-Scan Card Trigger Reliability

## Context

The auto-scan function is missing the card trigger regularly since this feature branch. Before the branch, the trigger used a simple two-signal approach: single fixed threshold (`sceneChangeThreshold: 0.03`) + YOLO detection. It was not perfect but very consistent. The new system introduced a complex `MotionBurstDetector` state machine, spatial `DetectionZone` filtering, and changed the reference frame lifecycle — which together introduced several bugs that cause real card placements to be rejected.

## Root Causes

Five bugs identified in the motion detection pipeline:

| # | Bug | Impact | Why it matters |
|---|-----|--------|----------------|
| 1 | `idleBaseline` never reset in `MotionBurstDetector.reset()` | HIGH | After first capture, stale baseline makes the adaptive peak threshold permanently stricter than warranted |
| 2 | Early-motion-stop guard (lines 237-244) rejects fast-settling cards | HIGH | Cards placed and stopped in < `settlementFrames` are classified as "hand removed" and reset |
| 3 | `burstMaxDiff` initialized to only the current frame's diff, not window peak | MEDIUM | Sharp initial spike followed by lower sustained motion (common drop-and-slide) under-reports the true peak |
| 4 | Zone filter uses strict full containment after calibration | MEDIUM | Cards placed slightly offset from the calibration position have YOLO boxes rejected |
| 5 | Reference cleared but first frame computes diff=0 before reference is established | LOW | Wastes a warmup frame; adds unnecessary latency post-capture |

## Fix Plan

### Fix 1: Reset `idleBaseline` in `reset()` (HIGH)

**File**: `MotionBurstDetector.swift`, line 143-154

Add `idleBaseline = 0` to the `reset()` method. Each detection cycle after a capture represents a new scene — the ambient noise floor should be re-established from current conditions, not carry forward previous card placement artifacts.

### Fix 2: Remove early-motion-stop guard (HIGH)

**File**: `MotionBurstDetector.swift`, lines 237-244 in `handleBurstDetectedState`

Remove the block that resets when `diff < threshold && consecutiveLowFrames > 1 && elapsedFrames < settlementFrames`. This conflates "card settled quickly" with "hand removed." The existing burst detection (`burstFrameCount >= 2`) and peak validation already provide sufficient anti-shadow protection.

### Fix 3: Track true window peak for `burstMaxDiff` (MEDIUM)

**File**: `MotionBurstDetector.swift`, lines 195-198 in `handleIdleState`

When burst is first detected, initialize `burstMaxDiff` from the max of all recent frames in the evaluation window, not just the current frame's diff. Add a `maxRecentDiffInWindow()` helper that scans the ring buffer. This ensures the peak validation evaluates the true maximum, which matters when card arrival produces an initial sharp spike followed by lower sustained motion.

### Fix 4: Use center-proximity for calibrated zone filtering (MEDIUM)

**File**: `CardPresenceTracker.swift`, lines 368-390 in `passesZoneFilter`

Replace `zone.contains(visionBox)` with `zone.containsCenter(of: visionBox)` for calibrated zones. The `containsCenter(of:)` method already exists in `DetectionZone` — it checks if the box center is within a radius of the zone center, allowing cards that grow larger or shift slightly from the calibration position to still pass. Uncalibrated zones keep strict containment.

### Fix 5: Move `checkReferenceDecay()` before diff computation (LOW)

**File**: `CardPresenceTracker.swift`, lines 234-235 in `process(pixelBuffer:)`

Reorder so `checkReferenceDecay()` runs before `calculateFrameDiff()`. After `markCaptured()` clears the reference, the first processed frame currently gets diff=0.0 because reference is empty. By establishing the reference first, we get a meaningful diff comparison on the very first post-reset frame.

### Fix 6: Reduce adaptive peak threshold multiplier (LOW-MEDIUM)

**File**: `MotionBurstDetector.swift`, line 217 in `handleBurstDetectedState`

Change `idleBaseline * 3.0` to `idleBaseline * 2.0`. A 3x multiplier rejects gently placed cards that produce diffs only 1.5-2x above ambient noise. The absolute floor (`minPeakThreshold / 5.0 = 0.01`) still prevents accepting pure noise.

## Files to Modify

1. `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/MotionBurstDetector.swift` — fixes 1, 2, 3, 6
2. `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/CardPresenceTracker.swift` — fixes 4, 5

## Test Changes

- Update `MotionBurstDetectorTests.swift`: test that `idleBaseline` is cleared by reset(); test fast-settling card triggers; test burstMaxDiff captures window peak
- Update `MotionBurstPeakTests.swift`: adjust threshold math for reduced multiplier; add gentle placement test case
- Update any existing tests that depend on the removed early-motion-stop guard

## Verification

1. Run `make ios-test` — all existing tests pass, updated tests verify fixes
2. Run `make ios-build` — app compiles cleanly
3. Test on device: place cards at varied speeds (gentle placement, quick drop, stack building) and verify trigger fires consistently
4. Monitor debug logs for rejection reasons — "No sharp peak" and "Motion stopped without settlement" should disappear
