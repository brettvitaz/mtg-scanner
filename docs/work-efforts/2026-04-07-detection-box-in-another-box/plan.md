# Plan: Prefer enclosing cards over nested feature boxes in scan mode

**Planned by:** Codex
**Date:** 2026-04-09

## Approach

Keep scan mode’s rectangle detector as the source of overlay geometry, but correct two flaws in the existing implementation. First, containment suppression must be order-independent: after IoU NMS, analyze containment relationships across the full candidate set and prefer the enclosing single-card candidate over nested feature boxes, while rejecting aggregate outer boxes that merely span multiple peer cards. Second, mode/orientation changes must reset scan-mode YOLO validation state synchronously on the same queue that processes frames so the first post-change frames cannot use stale cached validation.

## Implementation Steps

1. Rewrite `RectangleFilter` containment suppression so IoU NMS remains confidence-based, but containment decisions are made from pairwise relationships across all NMS survivors rather than greedy confidence order.
2. Reject aggregate outer boxes with multiple direct contained peers, suppress descendants of surviving non-aggregate ancestors, and keep crop mode unchanged.
3. Move `CardDetectionEngine` mode/orientation mutations and scan-YOLO resets onto `visionQueue`, and make frame processing read that state only after it reaches the same queue.
4. Replace the incorrect nested-box tests, add regressions for containment chains and post-reset YOLO cache behavior, and verify with the Xcode-backed `MTGScannerKitTests` target plus `git diff --check`.

Step 3 depends on step 2 only for the new regression surface; the queue-ordering fix is otherwise independent.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/RectangleFilter.swift` | Replace greedy containment suppression with order-independent containment analysis |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/CardDetectionEngine.swift` | Make scan validation reset and mode/orientation state changes deterministic on `visionQueue` |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RectangleFilterTests.swift` | Replace incorrect nested-box expectations and add containment-chain coverage |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CardDetectionEngineTests.swift` | Add regressions for immediate post-change validation and stale-generation refresh rejection |
| `docs/work-efforts/2026-04-07-detection-box-in-another-box/findings.md` | Record the goal, findings, correct high-level algorithm, and trade-offs |

## Risks and Open Questions

- Containment and YOLO support thresholds remain heuristic and may still need tuning against real camera input.
- Aggregate-box detection is more correct than greedy suppression for multi-card scenes, but it adds logic complexity and depends on a direct-child interpretation of the containment graph.
- Synchronous `visionQueue` resets eliminate stale-state races but make mode/orientation updates block until pending vision work reaches a safe point.
- Manual preview validation is still useful because the unit tests cover geometry and queue-ordering invariants, not full live-camera behavior.

## Verification Plan

- `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/CardDetectionEngineTests -only-testing:MTGScannerKitTests/ScanYOLOValidationStateTests -only-testing:MTGScannerKitTests/ScanYOLOSupportTests`
- `git diff --check`
