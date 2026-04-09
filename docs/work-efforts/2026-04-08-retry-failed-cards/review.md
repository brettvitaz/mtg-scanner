# Review: Retry Failed Cards

**Reviewed by:** Claude Sonnet 4.6
**Date:** 2026-04-08

## Summary

**What was requested:** Preserve failed recognition jobs so users can retry or dismiss them via an interactive badge instead of losing them silently.

**What was delivered:** `RecognitionQueue` now stores failed jobs in a private array and exposes `retryFailed()` / `clearFailed()`. The failed badge is a tappable button that presents an alert with Retry, Dismiss, and Cancel options. Both scan modes wire the new callbacks. Four new tests cover the retry and clear paths.

**Deferred items:** None. All requirements from `request.md` were delivered.

## Code Review Checklist

### 1. Correctness

**Result:** pass

`retryFailed()` resets `retryCount` to 0 so re-enqueued jobs get their one automatic retry. `failedCount` is kept in sync at all three mutation sites: `handleFailure`, the JPEG-encode guard in `process(job:)`, and `retryFailed()`/`clearFailed()`. The alert callbacks are optional; missing either produces a safe no-op. Cancellation via `cancelAll()` is unchanged and correctly does not touch `failedJobs`.

### 2. Simplicity

**Result:** pass

`retryFailed()` is 8 lines. `clearFailed()` is 2 lines. `handleFailure` is unchanged in length. Badge changes add ~12 lines. No new abstractions or protocols were introduced.

### 3. No Scope Creep

**Result:** pass

Only the five planned files were modified. No unrelated cleanup, no new settings, no per-card retry logic.

### 4. Tests

**Result:** pass

Four new tests in `RecognitionQueueRetryTests`:
- `testRetryFailedMovesJobsToPending` — verifies counts after `retryFailed()` before jobs process.
- `testRetryFailedJobsProcessAfterRetry` — end-to-end: failed → retried → completed.
- `testClearFailedRemovesAllFailedJobs` — verifies all failed jobs and count are cleared.
- `testRetryFailedResetsRetryCount` — verifies the recognize function is called 4 times total (2 original + 2 after retry), confirming the retry count was reset.

All tests would fail if the corresponding implementation were removed.

### 5. Safety

**Result:** pass

No force unwraps. All callbacks are called with `?()`. `retryFailed()` and `clearFailed()` are `@MainActor` methods called from `@MainActor` SwiftUI closures — no threading issues. No retain cycles: callbacks are plain closures, not stored properties on long-lived objects.

### 6. API Contract

**Result:** not applicable

iOS-only change. No backend schema or endpoints touched.

### 7. Artifacts and Observability

**Result:** not applicable

No recognition or detection logic was changed. Existing artifact production is unaffected.

### 8. Static Analysis

**Result:** pass

`make ios-lint` reports 0 violations across 77 files. The initial implementation pushed `RecognitionQueueTests` over the 200-line SwiftLint body-length limit; this was resolved by splitting tests into two classes and extracting helpers as `@MainActor` free functions — a structural fix, not a suppression.

## Verification Results

```
$ make ios-test
...
Test case 'RecognitionQueueRetryTests.testClearFailedRemovesAllFailedJobs()' passed (0.471s)
Test case 'RecognitionQueueRetryTests.testRetryFailedJobsProcessAfterRetry()' passed (0.633s)
Test case 'RecognitionQueueRetryTests.testRetryFailedMovesJobsToPending()' passed (0.303s)
Test case 'RecognitionQueueRetryTests.testRetryFailedResetsRetryCount()' passed (0.616s)
** TEST SUCCEEDED **

$ make ios-lint
Done linting! Found 0 violations, 0 serious in 77 files.
```

34 tests total pass (30 pre-existing + 4 new).

## Notes

The `Job` struct being `private` forced a manual counter rather than a computed property over the array. This is the simplest approach that satisfies Swift's access control rules — the alternative (making `Job` internal) would have exposed implementation details unnecessarily.
