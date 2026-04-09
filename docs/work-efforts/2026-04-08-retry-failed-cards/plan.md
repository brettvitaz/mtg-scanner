# Plan: Retry Failed Cards

**Planned by:** Claude Sonnet 4.6
**Date:** 2026-04-08

## Approach

`RecognitionQueue` currently discards jobs after one automatic retry, incrementing only a counter. The fix stores failed jobs in a private array so their images are retained. Two new public methods — `retryFailed()` and `clearFailed()` — let callers act on the accumulated failures. The badge view gains optional callbacks and an alert, and both call sites are updated to wire those callbacks through.

## Implementation Steps

1. **RecognitionQueue**: Replace the discard-on-second-failure path with `failedJobs.append(job)`. Keep `failedCount` as a `private(set) var` kept manually in sync (a computed property over the private `[Job]` array is not possible because `Job` is a private type, which Swift forbids exposing via a `private(set)` property). Add `retryFailed()` and `clearFailed()`.
2. **RecognitionQueueTests**: Add four new tests in a separate `RecognitionQueueRetryTests` class (split to stay within the 200-line SwiftLint limit). Extract shared helpers to free functions annotated `@MainActor`.
3. **RecognitionBadgeView**: Add `onRetryFailed` and `onClearFailed` optional callbacks and `@State private var showingFailedAlert`. Convert `failedBadge` from plain `Text` to a `Button` that sets `showingFailedAlert = true`. Attach an `.alert` to the outermost `VStack`.
4. **AutoScanView and ScanView**: Pass `onRetryFailed` and `onClearFailed` to both `RecognitionBadgeView` initialisations. Steps 3 and 4 can proceed in parallel; both depend on step 1.

## Files to Modify

| File | Change |
|------|--------|
| `Features/AutoScan/RecognitionQueue.swift` | Store failed jobs; add `retryFailed()` / `clearFailed()`; keep `failedCount` in sync |
| `Features/Shared/RecognitionBadgeView.swift` | Tappable failed badge, alert with Retry / Dismiss / Cancel |
| `Features/AutoScan/AutoScanView.swift` | Pass new callbacks to `RecognitionBadgeView` |
| `Features/Scan/ScanView.swift` | Pass new callbacks to `RecognitionBadgeView` |
| `Tests/MTGScannerKitTests/RecognitionQueueTests.swift` | New `RecognitionQueueRetryTests` class; shared helpers as free functions |

All paths relative to `apps/ios/MTGScannerKit/Sources/MTGScannerKit/`.

## Risks and Open Questions

- **`failedCount` sync**: Because `Job` is a private struct, Swift forbids `private(set) var failedJobs: [Job]`. The counter must be maintained manually at every mutation site — easy to miss. Addressed by auditing all three mutation points: `handleFailure`, `encodeJPEG` guard, and `retryFailed`/`clearFailed`.
- **`retryCount` reset**: If `retryCount` is not reset to 0 in `retryFailed()`, re-enqueued jobs skip their automatic retry and immediately re-enter the failed list on any error. Reset is critical.
- **SwiftLint body length**: Adding tests to `RecognitionQueueTests` pushes the class over the 200-line limit. Resolved by splitting into two classes in the same file with shared free-function helpers.

## Verification Plan

```bash
make ios-test   # all tests pass (30 existing + 4 new)
make ios-lint   # 0 violations
```
