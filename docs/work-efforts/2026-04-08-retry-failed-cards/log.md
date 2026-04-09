# Log: Retry Failed Cards

## Progress

### Step 1: Explored codebase and designed plan

**Status:** done

Explored the full scanning pipeline: `RecognitionQueue`, `RecognitionBadgeView`, `AutoScanView`, `ScanView`, and existing tests. Confirmed that failed jobs are discarded after one automatic retry with only a counter incremented, and that the badge has no interactive affordance. Designed the plan and documented it before writing any code.

Deviations from plan: none

---

### Step 2: Established baseline

**Status:** done

Ran `make ios-test`. All 30 pre-existing tests passed. No pre-existing failures.

Deviations from plan: none

---

### Step 3: Updated RecognitionQueue.swift

**Status:** done

Added `private var failedJobs: [Job] = []`. Updated `handleFailure` and the JPEG-encode guard in `process(job:)` to append to `failedJobs` and increment `failedCount`. Added `retryFailed()` and `clearFailed()`, each keeping `failedCount` in sync with `failedJobs`.

Initial attempt used `private(set) var failedJobs: [Job]` with a computed `failedCount`, but Swift rejected this: a `private(set)` property cannot have a type that uses a private type (`Job`). Reverted to a separate `private(set) var failedCount` kept manually in sync, and made `failedJobs` fully `private`.

Deviations from plan: `failedCount` is a manually-synced stored var rather than a computed property, due to Swift access control rules around private types.

---

### Step 4: Added tests for retryFailed and clearFailed

**Status:** done

Added four tests. Initially placed them in `RecognitionQueueTests`, which caused a SwiftLint `type_body_length` violation (239 lines, limit 200). Resolved by extracting the four new tests into a separate `RecognitionQueueRetryTests` class and promoting the shared `makeFailingQueue()` and `makeImage()` helpers to `@MainActor` free functions accessible to both classes.

Deviations from plan: Tests split into two classes rather than one; helpers promoted to free functions rather than kept as `extension RecognitionQueueTests` methods.

---

### Step 5: Updated RecognitionBadgeView.swift

**Status:** done

Added `onRetryFailed` and `onClearFailed` optional callback properties and `@State private var showingFailedAlert`. Converted `failedBadge` from a plain `Text` to a `Button`. Attached `.alert` with Retry, Dismiss, and Cancel actions to the outermost `VStack`.

Deviations from plan: none

---

### Step 6: Wired callbacks in AutoScanView and ScanView

**Status:** done

Added `onRetryFailed: recognitionQueue.retryFailed` and `onClearFailed: recognitionQueue.clearFailed` to the `RecognitionBadgeView` init in `AutoScanView.topBar`. Added the same in `ScanView.standardOverlay` via `autoScanViewModel.recognitionQueue`.

Deviations from plan: none

---

### Step 7: Ran final tests and lint

**Status:** done

`make ios-test`: 34 tests passed (30 pre-existing + 4 new). `TEST SUCCEEDED`.
`make ios-lint`: 0 violations, 0 serious in 77 files.

Deviations from plan: none

---
