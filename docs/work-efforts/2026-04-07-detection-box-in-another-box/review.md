# Review: Suppress nested detection boxes in scan mode

**Reviewed by:** Codex
**Date:** 2026-04-09

## Summary

**What was requested:** Stop scan mode from showing smaller detection boxes inside a larger card box and, if appropriate, use the existing YOLO detector to recognize that those inner boxes are really card features.

**What was delivered:** Reworked scan-mode containment suppression so enclosing single-card candidates beat nested feature boxes independently of confidence order, rejected aggregate outer boxes that span multiple peer cards, and made scan-mode YOLO cache resets deterministic across mode/orientation changes.

**Deferred items:** Live preview validation and possible threshold tuning still remain before the goal can be considered fully closed out in production behavior. No model retraining, tracker reset redesign, or scan UX redesign was attempted.

## Code Review Checklist

### 1. Correctness

**Result:** pass

The implementation addresses both parts of the request. `RectangleFilter` now decides containment from the full set of NMS survivors rather than greedy confidence order, which preserves the real enclosing card over nested card-feature boxes while still keeping peer cards by rejecting aggregate outers. `CardDetectionEngine` now applies mode/orientation changes and scan-YOLO cache resets on the same serial queue that processes frames, so stale validation results from the previous configuration cannot leak into the first post-change scan frames. The scan overlay still uses rectangle quads, so valid card overlays behave as before.

### 2. Simplicity

**Result:** pass

The changes stay within the existing detection architecture. YOLO is reused as a validator instead of replacing scan mode outright, and the extra logic is contained to small helper surfaces rather than introducing a new detector abstraction or mode split.

### 3. No Scope Creep

**Result:** pass

The work is limited to scan-mode detection, its supporting tests, and related documentation. No backend changes, recognition changes, UI redesign, or auto-scan state-machine work was added.

### 4. Tests

**Result:** pass

Added coverage for corrected containment behavior in `RectangleFilterTests`, queue-ordering and stale-generation behavior in `CardDetectionEngineTests`, and existing scan-mode support heuristics in `ScanYOLOSupportTests`. The focused simulator test run should target the `MTGScannerKitTests` scheme rather than package-level `swift test`.

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

- `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/CardDetectionEngineTests -only-testing:MTGScannerKitTests/ScanYOLOValidationStateTests -only-testing:MTGScannerKitTests/ScanYOLOSupportTests` — passed.
- `git diff --check` — passed.
- `xcodebuild test` using the `MTGScanner` app scheme with `-only-testing:MTGScannerKitTests/...` — not a valid path here because `MTGScannerKitTests` is not part of that scheme’s test plan.

## Notes

I am satisfied with this as a code-level fix because it corrects the two reviewer-identified logic errors and locks the intended invariants into tests. I am not satisfied calling the overall bug fully closed until live scan scenes are exercised against the original failure cases. The remaining work is operational rather than architectural: validate real preview behavior, tune thresholds if needed, and preserve the invariants documented in `findings.md`.
