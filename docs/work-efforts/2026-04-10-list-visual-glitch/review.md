# Review: Collections list rounding glitch

**Reviewed by:** OpenClaw subagent
**Date:** 2026-04-10

## Summary

**Verdict:** fail, architecture is improved but the fix is still not verified.

**What was requested:** Investigate and fix the delayed/glitchy rounded-corner transition on the top and bottom cells in the iOS Collections list during swipe-to-delete and press-and-hold.

**What was delivered:** Replaced section-level `.onDelete` handling in `LibraryView` with explicit row-level `.swipeActions(edge: .trailing, allowsFullSwipe: true)` for collection and deck rows, while preserving the existing `NavigationLink` and rename context-menu behavior.

**Assessment:** Based on the code, this is a better fix than the prior `List` style change. The earlier `.listStyle(.insetGrouped)` adjustment was broad and did not target the interaction path that differed from the working detail lists. This change instead aligns `LibraryView` with `CollectionDetailView` and `DeckDetailView`, which already use row-level swipe actions and are the closest architectural match for the desired behavior. That makes the current fix narrower, easier to justify, and more plausible. However, the task explicitly required reproducing and verifying top, middle, and bottom row behavior during both swipe-to-delete and press-and-hold, and there is still no direct manual validation showing the visual glitch is gone.

**Deferred items:** Manual interaction verification remains incomplete.

## Code Review Checklist

### 1. Correctness

**Result:** fail

The implementation is plausible and better targeted than the prior list-style change, because it moves Library deletion onto the same row-level swipe action pattern used by the working detail lists. That said, correctness is not fully established yet: the request covered both swipe-to-delete and press-and-hold behavior, while this code change only alters the swipe-delete mechanism and does not itself demonstrate that the long-press visual glitch is resolved.

### 2. Simplicity

**Result:** pass

The fix is limited to swapping section-level delete handling for row-level swipe actions on the existing rows. No new abstractions, helpers, or unrelated behavior branches were added.

### 3. No Scope Creep

**Result:** pass

Only the Library list delete interaction path and the task documentation were changed. No unrelated UI cleanup or list redesign was included.

### 4. Tests

**Result:** fail

No automated test covers this change, which is understandable for this specific SwiftUI interaction bug, but the requested manual verification was also not completed. For a UI-only change like this, the substitute for an automated test is direct simulator/device validation of the real interaction paths. That evidence is missing.

### 5. Safety

**Result:** pass

The change is UI-only, adds no force unwraps, does not alter threading, and preserves the existing delete operations by calling the same `LibraryViewModel` delete methods.

### 6. API Contract

**Result:** not applicable

No API or schema behavior changed.

### 7. Artifacts and Observability

**Result:** not applicable

The change does not touch recognition, detection, or debug artifact generation.

### 8. Static Analysis

**Result:** pass

The touched file passes targeted linting with `swiftlint lint apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/LibraryView.swift`. Repo-wide `make ios-lint` still fails due to pre-existing SwiftLint violations outside this task, including `AutoScanViewModel.swift`, `CardDetectionEngine.swift`, `AppModel.swift`, `RectangleFilter.swift`, `RecognitionQueueTests.swift`, `RectangleFilterTests.swift`, and `ScanYOLOSupportTests.swift`.

## Verification Results

- Baseline: `make ios-build` passed.
- Baseline: `make ios-lint` failed with pre-existing SwiftLint violations outside the touched files.
- Post-change: `make ios-build` passed.
- Post-change: `make ios-lint` failed with the same pre-existing SwiftLint violations.
- Post-change: `swiftlint lint apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/LibraryView.swift` passed.
- Post-change: build success confirms the row-level swipe action implementation is valid SwiftUI, but there is still no captured evidence that top, middle, and bottom rows were manually checked during swipe-to-delete and press-and-hold.

## Issues Found

1. **Manual verification required by the task is missing.** The request explicitly called for reproducing and verifying top, middle, and bottom row behavior during swipe-to-delete and press-and-hold. The current evidence is still limited to code inspection plus build/lint results, so the claimed visual fix remains unproven.
2. **Press-and-hold resolution is still only inferred, not demonstrated.** The new implementation changes the swipe-delete path by replacing section-level `.onDelete` with row-level `.swipeActions`, which is a sensible architectural match to the working detail lists. But the long-press interaction path still relies on the existing `contextMenu`, so this commit does not provide direct proof that the press-and-hold rounding glitch is fixed.

## Notes

- I could not perform a full interactive swipe/long-press visual check from this headless subagent session, so my verdict is based on code inspection plus build/lint verification.
- The missing `docs/plans/collections-list-rounding-glitch.md` file referenced in the request context was not present in this worktree.
- Compared with the prior `.listStyle(.insetGrouped)` fix, this row-level swipe action change is the better architectural direction because it targets the differing interaction implementation rather than the list's overall presentation style.
- If a task agent can run the simulator interactively and confirm the behavior on first, middle, and last rows, this change is otherwise clean and likely sufficient.
