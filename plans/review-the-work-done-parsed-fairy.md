# Review: PR #82 Fix1 — YOLO Overlay Coordinate Mismatch

## Context

The plan in `docs/plans/pr-82-plan-fix1.md` addressed a P0 correctness bug in `DetectionOverlayRenderer.updateYOLOOverlay()`. Raw YOLO normalized bounding boxes (0–1) were incorrectly multiplied by `sourceSize` (pixel dimensions like 3024×4032) before being passed to `yoloRectToVision()` / `rectToLayer()`, which expect normalized [0,1] inputs. The result was overlay rectangles drawn at nonsensical screen positions (negative coordinates, wildly off-screen).

The fix was implemented in commit `b82862a` (or the HEAD commit introducing these changes).

---

## Code Review

### 1. Correctness — PASS

The change is exactly right. The plan diagnosed the bug accurately:
- `box.rect` is already normalized (0–1, top-left origin) per YOLO output spec
- Multiplying by `sourceSize` produced pixel-space values
- `yoloRectToVision()` then did `1.0 - maxY` on pixel values (e.g., `1.0 - 4032 = -4031`)
- `layerPointConverted(fromCaptureDevicePoint:)` expects [0,1]

The fix correctly passes `box.rect` directly to `yoloRectToVision(box.rect)`, matching the pipeline used everywhere else in the file (Vision normalized → Y-flip → `layerPointConverted`).

Removing the `sourceSize` parameter is also correct: the method has no callers in the current codebase, so no caller updates are needed, and the parameter served only the now-deleted scaling block.

### 2. Simplicity — PASS

The change removes 6 lines and simplifies the loop body from a 4-line `CGRect` construction + scaling to a single expression. No unnecessary abstractions introduced.

### 3. No scope creep — PASS

Only the two changes specified in the plan were made:
1. Removed `sourceSize: CGSize` parameter from `updateYOLOOverlay` signature
2. Removed the pixel-space scaling block

No other files touched.

### 4. Tests — FAIL (pre-existing, not introduced)

`DetectionOverlayRendererTests.swift` has a known bug documented in the findings:
- `detectionLayerPoolCount = 2` with comment "zone overlay layer + YOLO debug overlay layer" — but no zone overlay layer exists in this class. Only the YOLO overlay layer exists.
- All layer-count assertions (`2 + detectionLayerPoolCount`, `1 + detectionLayerPoolCount`, etc.) are off by +1.
- This is a **pre-existing** test bug (issue #18 in the findings), not introduced by this fix.

The fix itself has no unit test for `updateYOLOOverlay` directly, but this is acceptable since the method is currently dead code (no callers) and was already untested before. The report notes `make ios-test` produced the same 4 pre-existing failures (unrelated to this change).

### 5. Safety — PASS

No force unwraps introduced. Thread safety unchanged (`updateYOLOOverlay` already documented as main-thread only, unchanged). `CATransaction.setDisableActions(true)` still present. No retain cycles introduced.

### 6. API contract — PASS

`updateYOLOOverlay` is a debug-only internal method with no callers. No public API surface changed.

### 7. Artifacts and observability — PASS

No recognition/detection artifacts affected. This is a debug overlay method.

### 8. Static analysis — PASS

Report confirms: `make ios-lint` → 0 violations, `make ios-build` → BUILD SUCCEEDED.

---

## Summary

The fix correctly resolves the P0 YOLO overlay coordinate bug as specified in the plan. The implementation is clean, minimal, and passes lint/build.

**One outstanding issue (not introduced by this fix):** the `detectionLayerPoolCount = 2` constant in `DetectionOverlayRendererTests.swift` is wrong — it should be `1`. This is issue #18 from the findings and was present before this change. It should be addressed as a follow-up.

---

## Outstanding Items (from pr-82-findings.md — not yet implemented)

| Priority | Issue | File | Fix |
|----------|-------|------|-----|
| P1 | #7 — `resetDetectionZone()` leaves stale `detectionZone` on UI | `AutoScanViewModel.swift:145-148` | Add `detectionZone = nil` |
| P1 | #17 — capture failure permanently blocks auto-scan | `AutoScanViewModel.swift:232-261` | Call `presenceTracker.markCaptured()` on early return |
| P2 | #9 — unused `sourceSize`/`videoSize` params in `DetectionZone.calibrated()` | `DetectionZone.swift:135-210` | Remove params + update one test caller |
| P2 | #12 — motion burst settings not clamped on load | `AppModel.swift` | Add clamp helpers on UserDefaults load |
| P3 | #18 — `detectionLayerPoolCount = 2` should be `1` | `DetectionOverlayRendererTests.swift` | Change constant and fix all count assertions |

---

## Recommendation

The P0 fix (issue #1) is correct and complete. Proceed to address the two P1 items next — specifically #17 (capture failure blocking auto-scan permanently) which has the highest functional impact on the auto-scan feature.
