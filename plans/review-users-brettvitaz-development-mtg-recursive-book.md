# PR-82 Remaining Fixes Plan

## Context

PR #82 had 10 actionable comments. P0 fix (#1 - YOLO overlay coordinate scaling) is already applied. This plan covers the 8 remaining fixes: one perma-block bug, one thread safety fix, three logic/correctness fixes, one API cleanup, and three test fixes.

## Fix List

### 1. #17 (High) — Clear `pendingCapture` on capture failure
**File:** `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift` (line 237)

**Problem:** When `capturePhoto()` returns nil, `triggerCapture()` returns without calling `presenceTracker.markCaptured()`. The tracker's `pendingCapture` stays true forever, permanently blocking auto-scan.

**Change:** Add one line before the early return:
```swift
guard let payload = await captureCoordinator?.capturePhoto() else {
    presenceTracker.markCaptured()  // NEW
    captureState = .watching
    statusMessage = "Capture failed — watching…"
    return
}
```

### 2. #7 (P1) — Clear `detectionZone` in `resetDetectionZone()`
**File:** `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift` (line 145)

**Problem:** `resetDetectionZone()` calls `presenceTracker.resetZone()` but doesn't set `self.detectionZone = nil`. SwiftUI views keep rendering a stale zone overlay.

**Change:** Add one line:
```swift
func resetDetectionZone() {
    presenceTracker.resetZone()
    detectionZone = nil       // NEW
    isCalibrated = false
}
```

### 3. #12 (P2) — Clamp motion burst settings on load
**File:** `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/AppModel.swift` (lines 85-88)

**Problem:** `motionBurstMotionThreshold` and `motionBurstMinPeakThreshold` loaded from UserDefaults with zero-guard only, no range clamping. Corrupted defaults can cause invalid configs.

**Change:** Add two clamp helpers (following existing `clampAutoScanConfidence` pattern):
```swift
private static func clampMotionBurstMotionThreshold(_ value: Double) -> Double {
    guard value > 0 else { return 0.015 }
    return min(max(value, 0.005), 0.050)
}
private static func clampMotionBurstMinPeakThreshold(_ value: Double) -> Double {
    guard value > 0 else { return 0.05 }
    return min(max(value, 0.020), 0.100)
}
```
Wrap the init load values with these helpers (lines 86, 88).

### 4. #8 (P2) — Order `recentDiffs` chronologically from ring buffer
**File:** `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/MotionBurstDetector.swift` (line 162)

**Problem:** `diffHistory.suffix(...)` returns array-tail order, not chronological order, for a wrapped ring buffer.

**Change:** Add a helper and update `currentMetrics()`:
```swift
private func recentDiffs(count: Int) -> [Float] {
    let actualCount = min(count, frameIndex)
    guard actualCount > 0 else { return [] }
    var result = [Float](repeating: 0.0, count: actualCount)
    for i in 0..<actualCount {
        let idx = (frameIndex - actualCount + i) % configuration.burstWindowSize
        result[i] = diffHistory[idx]
    }
    return result
}
```
Replace line 162: `recentDiffs: recentDiffs(count: configuration.burstWindowSize),`

### 5. #9 (P2) — Remove unused params from `DetectionZone.calibrated()`
**Files:**
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/DetectionZone.swift` (lines 135-140)
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift` (lines 246-250)
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/DetectionZoneTests.swift` (lines 60-64, 86)

**Problem:** `sourceSize` and `videoSize` params accepted but never used — method operates purely on normalized coords.

**Changes:**
1. Remove `sourceSize: CGSize, videoSize: CGSize` from `calibrated(fromYOLO:tolerance:)` signature
2. Update caller in `AutoScanViewModel.swift` (line 246-250):
   ```swift
   let calibratedZone = DetectionZone.calibrated(fromYOLO: box)
   ```
   Note: `sourceSize` and `videoSize` vars can be removed from this block.
3. Update two test callers in `DetectionZoneTests.swift`

### 6. #18 (P3) — Correct `detectionLayerPoolCount` in tests
**File:** `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/DetectionOverlayRendererTests.swift` (line 10)

**Problem:** Constant = 2 but only 1 non-pool layer exists (YOLO debug overlay). All count assertions are off by +1.

**Change:**
```swift
private var detectionLayerPoolCount: Int {
    1 // YOLO debug overlay layer only
}
```
All assertions dynamically reference this constant so no other changes needed.

### 7. #16 (P1) — Thread safety: capture `useLegacyDetection` on queue
**File:** `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/CardPresenceTracker.swift` (lines 224-236, 266-270)

**Problem:** `determineTrigger` reads `useLegacyDetection` (plain `var`, no sync) on `presenceQueue` while it can be written from main thread — data race.

**Change:** Capture `useLegacyDetection` inside `process()` on the queue, pass to `determineTrigger`:
```swift
private func process(pixelBuffer: CVPixelBuffer) {
    let motionZone = detectionZone?.effectiveRect
    let samples = analyzer.sample(pixelBuffer, zone: motionZone)
    lastSamples = samples
    #if DEBUG
    logFrameInfo(pixelBuffer: pixelBuffer, samples: samples, motionZone: motionZone)
    #endif
    let diff = calculateFrameDiff(samples: samples)
    checkReferenceDecay()
    let legacyMode = useLegacyDetection    // NEW: capture once on queue
    let shouldTrigger = determineTrigger(diff: diff, legacyMode: legacyMode)  // NEW param
    sendDebugMetricsIfEnabled()
    #if DEBUG
    logDetectionState(diff: diff, shouldTrigger: shouldTrigger)
    #endif
    guard shouldTrigger else { return }
    processTriggeredFrame(pixelBuffer: pixelBuffer)
}

private func determineTrigger(diff: Float, legacyMode: Bool) -> Bool {  // ADD PARAM
    legacyMode
        ? diff >= burstConfiguration.motionThreshold
        : burstDetector.process(diff: diff)
}
```

### 8. #15 (P3) — Replace `Thread.sleep` with deterministic testing
**Files:**
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/MotionBurstDetector.swift` (property declaration)
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/MotionBurstDecayTests.swift` (4 Thread.sleep calls)

**Problem:** Tests use `Thread.sleep` which is flaky under CI load.

**Change to MotionBurstDetector.swift:** Expose `lastReferenceUpdate` for testing:
```swift
private(set) var lastReferenceUpdate: Date = Date()
```

**Change to MotionBurstDecayTests.swift:** Remove all Thread.sleep calls, set `lastReferenceUpdate` directly using `@testable import`:
- `testReferenceDecayTimeout`: Set `detector.lastReferenceUpdate = Date(timeIntervalSinceNow: -2.0)` instead of sleeping
- `testReferenceDecayDoesNotTriggerWhenActive`: Same approach
- `testMarkReferenceUpdatedResetsTimer`: No sleep needed — call `markReferenceUpdated()` then check immediately

## Verification

1. `make ios-lint` — SwiftLint passes
2. `make ios-build` — Build succeeds
3. `make ios-test` — All tests pass (pre-existing failures unrelated to these changes)
