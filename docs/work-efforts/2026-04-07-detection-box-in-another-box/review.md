# Review: Suppress nested detection boxes in scan mode

**Reviewed by:** Codex
**Date:** 2026-04-07

## Summary

**What was requested:** Stop scan mode from showing smaller detection boxes inside a larger card box and, if appropriate, use the existing YOLO detector to recognize that those inner boxes are really card features.

**What was delivered:** Added containment-based nested-box suppression to the scan-mode rectangle filter and added throttled YOLO validation in scan mode so rectangle proposals must also look like real cards semantically before they reach overlay tracking.

**Deferred items:** Manual threshold tuning on live camera input remains recommended. No model retraining or scan UX redesign was attempted.

## Code Review Checklist

### 1. Correctness

**Result:** pass

The implementation addresses both parts of the request. `RectangleFilter` now removes substantially contained inner rectangles even when the inner box has higher confidence, and `CardDetectionEngine` uses YOLO support checks to reject card-feature rectangles that survive geometric filtering. The scan overlay still uses rectangle quads, so valid card overlays behave as before.

### 2. Simplicity

**Result:** pass

The changes stay within the existing detection architecture. YOLO is reused as a validator instead of replacing scan mode outright, and the extra logic is contained to small helper surfaces rather than introducing a new detector abstraction or mode split.

### 3. No Scope Creep

**Result:** pass

The work is limited to scan-mode detection, its supporting tests, and related documentation. No backend changes, recognition changes, UI redesign, or auto-scan state-machine work was added.

### 4. Tests

**Result:** pass

Added coverage for containment behavior in `RectangleFilterTests` and created `ScanYOLOSupportTests` for scan-mode support heuristics and coordinate conversion. The focused simulator test run for `RectangleFilterTests`, `ScanYOLOSupportTests`, and `YOLOCardDetectorTests` passed on the `MTGScannerKitTests` scheme.

### 5. Safety

**Result:** pass

No secrets or destructive operations were introduced. The new scan-mode state is still confined to the existing serial `visionQueue`, and YOLO failure falls back to rectangle-only behavior instead of silently dropping all detections.

### 6. API Contract

**Result:** not applicable

No external API or schema changed. The richer `RectangleFilter.FilterResult` is an internal implementation detail used by the scan-mode engine.

### 7. Artifacts and Observability

**Result:** pass

Added targeted debug logging in scan mode so containment suppression, YOLO acceptance/rejection, and fallback behavior can be inspected during threshold tuning. Existing overlay output and tracker behavior remain observable through the same pipeline.

### 8. Static Analysis

**Result:** pass

`git diff --check` passed. The simulator build also succeeded with the new code. No new lint suppressions were added in the modified files.

## Verification Results

- `xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -sdk iphonesimulator -configuration Debug build` — passed.
- `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/ScanYOLOSupportTests -only-testing:MTGScannerKitTests/YOLOCardDetectorTests` — passed.
- `git diff --check` — passed.
- `xcodebuild test` using the `MTGScanner` app scheme with `-only-testing:MTGScannerKitTests/...` — not a valid path here because `MTGScannerKitTests` is not part of that scheme’s test plan.

## Notes

The main remaining risk is threshold tuning on real scan scenes. If preview behavior still rejects valid cards or keeps too many false positives, tune the containment, IoU, coverage, cache TTL, and validation-stride constants in the scan detection helpers using the new debug output as guidance.
