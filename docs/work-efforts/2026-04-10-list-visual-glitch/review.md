# Review: Collections list rounding glitch

**Reviewed by:** OpenClaw subagent
**Date:** 2026-04-10

## Summary

**Verdict:** fail, plausible fix but not yet adequately verified.

**What was requested:** Investigate and fix the delayed/glitchy rounded-corner transition on the top and bottom cells in the iOS Collections list during swipe-to-delete and press-and-hold.

**What was delivered:** Replaced section-level `.onDelete` handling in `LibraryView` with explicit row-level `.swipeActions(edge: .trailing, allowsFullSwipe: true)` for collection and deck rows, while preserving the existing `NavigationLink` and rename context-menu behavior.

**Assessment:** Investigation did not find any custom row clipping, masking, corner radius, or first/last-row-specific background treatment in the Library list. The notable difference from the detail lists, which already animate correctly, was that Library rows used section-level `.onDelete` instead of explicit row-level swipe actions. Aligning the Library list with the detail-list deletion pattern is a narrow, plausible fix for the delayed boundary-row rounding transition. However, the task required reproducing and verifying the interaction on top, middle, and bottom rows during swipe-to-delete and press-and-hold, and that direct visual evidence is still missing from this headless session.

**Deferred items:** Verification remains incomplete.

## Code Review Checklist

### 1. Correctness

**Result:** pass

The change targets the most relevant behavioral difference in the Library list itself: deletion is now attached to each row via `.swipeActions`, matching the detail lists that already behave correctly. That keeps navigation and context menus intact while avoiding reliance on section-level `.onDelete` for the affected interaction path.

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

1. **Manual verification required by the task is missing.** The request explicitly called for reproducing and verifying top, middle, and bottom row behavior during swipe-to-delete and press-and-hold. The current work only shows build, lint, install, and launch evidence, so the claimed fix is still unproven.
2. **The prior review note understated existing lint failures.** `make ios-lint` currently reports additional pre-existing violations beyond the four files originally listed. This does not block the UI fix itself, but the review record should be accurate.

## Notes

- I could not perform a full interactive swipe/long-press visual check from this headless subagent session, so my verdict is based on code inspection plus build/lint verification.
- The missing `docs/plans/collections-list-rounding-glitch.md` file referenced in the request context was not present in this worktree.
- If a task agent can run the simulator interactively and confirm the behavior on first, middle, and last rows, this change is otherwise clean and likely sufficient.
