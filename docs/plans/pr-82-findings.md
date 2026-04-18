# Copilot PR #82 Comments Analysis

## Context
Copilot generated 10 inline comments on PR #82. This plan assesses which are actionable bugs/issues and what to do about each.

## Already Addressed (no action needed)

| # | Comment | Status |
|---|---------|--------|
| 6 | setupDetectionLayer redundant layer operations | Fixed — only `addSublayer`, no `insertSublayer` |
| 2 | updateZoneOverlay falls back to .fullFrame | Fixed — method no longer exists |
| 4 | ScanView passes .fullFrame for nil zone | Fixed — detectionZone logic moved to AutoScanViewModel |
| 5 | SettingsView @Environment(\.cardDetectionZoneReset) unavailable | Fixed — now uses AppModel directly |
| 11 | MotionBurstConfiguration.validate() not called | Fixed — values clamped inline in init |
| 10 | pixelBounds missing clamping | Fixed — clamping present in pixelBounds |
| 13 | passesZoneFilter missing containment/size checks | Fixed — now checks contained + largeEnough + portrait |

## Actionable Issues Remaining (10 issues)

### P0 — Real bugs (correctness/functional)

**#1 / #14: DetectionOverlayRenderer.swift — YOLO overlay scales normalized boxes by sourceSize**
- **Problem**: `updateYOLOOverlay` multiplies `box.rect` by `sourceSize` (pixel space), then passes to `yoloRectToVision`/`rectToLayer` which expect normalized coords. This produces incorrect overlay rectangles.
- **Fix**: Remove `sourceSize` scaling. Pass `box.rect` directly to `yoloRectToVision(box.rect)`. Remove `sourceSize` parameter from `updateYOLOOverlay` signature.
- **Investigation**: Confirmed. `box.rect` is normalized (0–1, top-left origin). Scaling by sourceSize (e.g., 3024x4032) produces pixel values like x:604, then `yoloRectToVision` does `1.0 - maxY = -4031`. Fed into Apple's `layerPointConverted` which expects [0,1]. No callers exist in the codebase — dead debug API until wired up.

### P1 — Data integrity bugs

**#3: AutoScanViewModel.swift — stop() sets detectionZone=nil but it's redundant**
- **Status**: Not a bug — harmless no-op confirmed via investigation.
- **Analysis**: `stop()` calls `presenceTracker.resetZone()` (line 135) then `detectionZone = nil` (line 136). The setter calls `presenceTracker.setZone(nil)` which has an idempotent guard (`guard self.detectionZone != zone else { return }`). Calling it twice is harmless — the second call short-circuits instantly. No functional impact, no race condition risk beyond negligible extra dispatch work. Leave as-is (or remove `resetZone()` for cleanliness only).

**#7: AutoScanViewModel.swift — resetDetectionZone() doesn't clear detectionZone**
- **Status**: Confirmed real bug.
- **Problem**: `resetDetectionZone()` calls `presenceTracker.resetZone()` and sets `isCalibrated = false`, but `detectionZone` still holds the old calibrated value. SwiftUI views bound to this property continue rendering a stale zone overlay after reset.
- **Fix**: Add `detectionZone = nil` line in `resetDetectionZone()`. File: `AutoScanViewModel.swift:145-148`.

**#16: CardPresenceTracker.swift — determineTrigger reads mutable state**
- **Problem**: `determineTrigger` reads `useLegacyDetection`, `burstConfiguration.motionThreshold` which are mutable from other threads.
- **Fix**: These are all called within `presenceQueue` serial queue context, so they're protected by queue serialization. However, explicit queue-confined copies would be cleaner. Assess whether current queue-based protection is sufficient or if atomics/queue-confined copies are needed.

### P2 — Logic bugs (correctness edge cases)

**#9: DetectionZone.swift — calibrated(fromYOLO:sourceSize:videoSize:) unused parameters**
- **Status**: Confirmed real bug.
- **Problem**: `sourceSize` and `videoSize` parameters accepted but never used in function body.
- **Investigation**: Exactly one caller exists (test file), passing identical CGSize values for both params. Method operates purely on normalized 0–1 coordinates, not pixel dimensions.
- **Fix**: Remove both parameters from signature and update the single test caller. File: `DetectionZone.swift:135-210`.

**#17: AutoScanViewModel.swift — capturePhoto nil doesn't clear pendingCapture**
- **Status**: Confirmed high-severity bug (blocks auto-scan permanently).
- **Problem**: When `capturePhoto()` returns nil, `triggerCapture()` resets `captureState = .watching` and returns early. It does NOT call `presenceTracker.markCaptured()`. The tracker's `pendingCapture` stays true forever. Next card drop hits the guard (`guard !pendingCapture else { return }`) and never fires a signal — auto-scan permanently blocked until app relaunch.
- **Fix**: In `triggerCapture()` early-return path (line 237–240), call `presenceTracker.markCaptured()` before returning. File: `AutoScanViewModel.swift:232-261`.

**#18: DetectionOverlayRendererTests.swift — detectionLayerPoolCount assumes 2 non-pool layers**
- **Status**: Confirmed real bug (all count assertions off by +1).
- **Problem**: Test constant `detectionLayerPoolCount = 2` with comment "zone overlay layer + YOLO debug overlay layer" but only the YOLO overlay layer exists. No zone overlay layer in this class. All layer count assertions using this constant are wrong.
- **Fix**: Change to `1 // YOLO debug overlay layer only`. Affected: testUpdateWithNoDetectionsClearsAllLayers (line 25), testUpdateAddsLayersToParentAsPoolGrows (lines 39, 42), testUpdateDoesNotShrinkPoolWhenDetectionCountDecreases (lines 52, 56). File: `DetectionOverlayRendererTests.swift`.

### P3 — Test issues

**#8: MotionBurstDetector.swift — recentDiffs ring buffer order scrambled**
- **Problem**: `currentMetrics()` uses `diffHistory.suffix(...)` on a ring buffer, producing non-chronological order for the debug overlay sparkline.
- **Fix**: Implement ordered iteration using modular indexing from `(frameIndex - count) % size`. The suggestion in the comment provides a full `orderedRecentDiffs()` replacement.

**#15: MotionBurstDecayTests.swift — Thread.sleep flaky tests**
- **Problem**: Tests use `Thread.sleep(forTimeInterval:)` which is flaky under CI load.
- **Fix**: Inject a clock/date provider or expose `lastReferenceUpdate` for testing instead of sleeping.

**#12: AppModel.swift — Motion burst settings not clamped on load**
- **Problem**: `motionBurstMotionThreshold` and `motionBurstMinPeakThreshold` loaded from UserDefaults without clamping to valid ranges. Corrupted defaults can cause invalid configs.
- **Fix**: Add clamp helpers (like existing `clampAutoScanConfidence`) and apply on load.

## Recommended Action Plan

1. **Fix #1** (P0) — Remove sourceSize scaling in updateYOLOOverlay
2. **Fix #7** (P1) — Add detectionZone = nil in resetDetectionZone()
3. **Fix #17** (P2) — Clear pendingCapture on capture failure
4. **Fix #8** (P2) — Order recentDiffs chronologically from ring buffer
5. **Fix #12** (P2) — Clamp motion burst settings on load
6. **Fix #18** (P3) — Correct detectionLayerPoolCount in tests
7. **Assess #9** (P2) — Decide whether to remove unused params or implement mapping
8. **Assess #16** (P1) — Confirm queue protection is sufficient or add explicit copies
9. **Fix #3** (P1) — Remove redundant resetZone/detectionZone=setNil pattern
10. **Fix #15** (P3) — Replace Thread.sleep with deterministic testing approach

## Verification
- `make ios-lint` — SwiftLint passes
- `make ios-test` — All tests pass
- Manual testing: verify YOLO overlay shows correctly on camera, reset zone clears overlay, capture failure doesn't lock auto-scan
