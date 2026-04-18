# PR #82 Comments — Investigation & Fix Report

**Date:** 2026-04-17  
**Scope:** Investigated all 10 actionable comments remaining after Copilot's batch of 7 were fixed. Implemented the P0 fix (comment #1). Updated `pr-82-findings.md` with investigation results and revised priority ordering.

---

## Verification Results

| Comment | Verdict | Severity |
|---------|---------|----------|
| **#1 / #14** — YOLO overlay scales normalized boxes by sourceSize | **Real bug** (confirmed) | P0 |
| **#3** — stop() double resetZone/setZone(nil) | **Not a bug** — `setZone` has idempotent guard (`guard self.detectionZone != zone else { return }`) | N/A |
| **#7** — resetDetectionZone() stale zone on UI | **Real bug** (confirmed) | P1 |
| **#9** — DetectionZone.calibrated unused sourceSize/videoSize params | **Real bug** (confirmed) | P2 |
| **#17** — capturePhoto nil leaves pendingCapture = true forever | **High-severity bug** (confirmed) | P1 |
| **#18** — detectionLayerPoolCount = 2 but only 1 non-pool layer exists | **Real bug** (confirmed) | P3 |

### Details

**#1 / #14 — YOLO Overlay Coordinate Bug (P0)**  
`updateYOLOOverlay` multiplied `box.rect` by `sourceSize`, converting normalized coords [0,1] into pixel values like x:604. These were fed to `yoloRectToVision()`, which does `1.0 - maxY` — producing nonsensical negative coordinates (e.g., y:-1511). Those were then passed to Apple's `layerPointConverted(fromCaptureDevicePoint:)`, which expects [0,1] normalized input. Result: overlay rectangles drawn at wrong screen positions. No callers exist in the codebase — dead debug API until wired up.

**#3 — stop() Redundancy (Not a Bug)**  
`stop()` calls `presenceTracker.resetZone()` then sets `detectionZone = nil`. The setter invokes `setZone(nil)` which has an idempotent guard on line 167 of CardPresenceTracker.swift. The second call short-circuits instantly with zero functional impact. No race condition risk beyond negligible extra dispatch work. Leave as-is or remove for cleanliness only.

**#7 — resetDetectionZone Stale Zone (P1)**  
`resetDetectionZone()` calls `presenceTracker.resetZone()` and sets `isCalibrated = false`, but never clears `detectionZone`. The VM's `@Observable` property retains its old value, so SwiftUI views continue rendering a stale zone overlay after the user hits reset.

**#9 — Unused Parameters (P2)**  
`calibrated(fromYOLO:sourceSize:videoSize:)` declares both size parameters but never reads them. Method operates purely on normalized 0–1 coordinates. Exactly one caller exists in test code, passing identical CGSize values for both params. No functional impact from removal.

**#17 — Capture Failure Permanently Blocks Auto-Scan (High Severity)**  
When `capturePhoto()` returns nil, `triggerCapture()` resets `captureState = .watching` and returns early without calling `presenceTracker.markCaptured()`. The tracker's `pendingCapture` flag stays true forever. The next card dropped into the scanner hits the guard (`guard !pendingCapture else { return }`) and never fires a signal — auto-scan is permanently blocked until app relaunch.

**#18 — Wrong Test Constant (P3)**  
`detectionLayerPoolCount = 2` with comment "zone overlay layer + YOLO debug overlay layer" but only the YOLO overlay layer exists in this class. No zone overlay layer exists anywhere. All layer count assertions using this constant are off by +1.

---

## Fix Implemented: Comment #1 (YOLO Overlay)

**File:** `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Overlay/DetectionOverlayRenderer.swift`

### Changes
1. Removed unused `sourceSize: CGSize` parameter from `updateYOLOOverlay()` signature (line 50)
2. Removed the pixel-space scaling block that multiplied normalized coords by sourceSize (was lines 64–69)
3. Now passes `box.rect` directly through `yoloRectToVision(box.rect)` → `rectToLayer()` as intended

### Diff
```diff
-    func updateYOLOOverlay(boxes: [CardBoundingBox], sourceSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer) {
+    func updateYOLOOverlay(boxes: [CardBoundingBox], previewLayer: AVCaptureVideoPreviewLayer) {
         ...
         for box in boxes {
-            let rect = CGRect(
-                x: box.rect.minX * sourceSize.width,
-                y: box.rect.minY * sourceSize.height,
-                width: box.rect.width * sourceSize.width,
-                height: box.rect.height * sourceSize.height
-            )
-            let screenRect = rectToLayer(yoloRectToVision(rect), previewLayer: previewLayer)
+            let screenRect = rectToLayer(yoloRectToVision(box.rect), previewLayer: previewLayer)
             path.append(UIBezierPath(rect: screenRect))
         }
```

### Verification
- `make ios-lint`: **0 violations, passed** (was 0 before change)
- `make ios-build`: **BUILD SUCCEEDED**
- `make ios-test`: same 4 pre-existing failures (unrelated to this change)
- No callers exist in the codebase — dead debug API until wired up

---

## Outstanding Items for Future Work

1. **#7** (P1) — Add `detectionZone = nil` in `resetDetectionZone()` at `AutoScanViewModel.swift:145-148`. One line fix.
2. **#17** (High) — Call `presenceTracker.markCaptured()` in the early-return path of `triggerCapture()`. Blocks auto-scan permanently if capture fails once.
3. **#9** (P2) — Remove unused `sourceSize`/`videoSize` params from `DetectionZone.calibrated()` and update one test caller.
4. **#18** (P3) — Change `detectionLayerPoolCount = 2` to `1` in `DetectionOverlayRendererTests.swift`; fix all count assertions using the constant.
5. **#12** (P2) — Add clamp helpers for motion burst settings on load from UserDefaults (partially mitigated by slider bounds).

---

## Updated Artifacts

- **`docs/plans/pr-82-findings.md`** — Updated with investigation status, severity labels, and revised action plan ordering (P0 → P1 → P2 → P3)
- **`docs/plans/pr-82-plan-fix1.md`** — Standalone fix plan for comment #1 (now redundant since fix is applied directly to code)
