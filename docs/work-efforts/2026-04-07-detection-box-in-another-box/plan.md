# Plan: Suppress nested detection boxes in scan mode

**Planned by:** Codex
**Date:** 2026-04-07

## Approach

Keep scan mode’s rectangle detector as the source of overlay geometry, then harden it in two stages. First, suppress smaller observations substantially contained inside a larger accepted rectangle. Second, validate the remaining scan-mode rectangles against the existing YOLO card detector so card-internal rectangular features do not survive just because they look card-shaped geometrically. Throttle and cache YOLO validation so scan mode stays responsive and falls back to rectangle-only behavior if YOLO is unavailable.

## Implementation Steps

1. Extend `RectangleFilter` to preserve current IoU NMS, then add containment-based nested-box suppression plus helpers and thresholds that can be reused by tests.
2. Update `CardDetectionEngine` scan-mode flow to consume the richer rectangle-filter result, run throttled YOLO validation on scan frames, and reject unsupported rectangles while keeping rectangle quads as the final overlay geometry.
3. Add focused tests for containment suppression and YOLO support heuristics, including small-feature rejection and coordinate conversion.
4. Verify with simulator build/test commands and `git diff --check`.

Steps 2 and 3 depend on step 1 establishing the containment behavior and helper surfaces.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/RectangleFilter.swift` | Add containment suppression, helper metrics, and richer filter result reporting |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/CardDetectionEngine.swift` | Add scan-mode YOLO validation, validation caching/throttling, and debug logging |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RectangleFilterTests.swift` | Add nested-box and containment behavior coverage |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/ScanYOLOSupportTests.swift` | Add focused tests for scan-mode YOLO support heuristics |

## Risks and Open Questions

- Thresholds for containment, IoU, and coverage are heuristic and may need tuning against real camera input.
- The user’s report suggested smaller nested boxes are usually card features, so the implementation should prefer rejecting inner boxes over choosing by confidence.
- Using YOLO as a validator is lower risk than replacing scan mode with YOLO, but it still adds compute cost; caching and stride-based refresh should keep that manageable.
- Manual preview validation is still useful because the unit tests cover geometry and support logic, not live camera scenes.

## Verification Plan

- `xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`
- `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/ScanYOLOSupportTests -only-testing:MTGScannerKitTests/YOLOCardDetectorTests`
- `git diff --check`
