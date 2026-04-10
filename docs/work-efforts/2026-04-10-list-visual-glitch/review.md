# Review: Collections list rounding glitch

**Reviewed by:** OpenClaw subagent
**Date:** 2026-04-10

## Summary

**What was requested:** Investigate and fix the delayed/glitchy rounded-corner transition on the top and bottom cells in the iOS Collections list during swipe-to-delete and press-and-hold.

**What was delivered:** Explicitly set the Library screen `List` to `.insetGrouped` so the Collections section uses the same stable grouped row styling as the detail lists, which narrows the fix to the affected surface without redesigning row content or interaction handlers.

**Deferred items:** None.

## Code Review Checklist

### 1. Correctness

**Result:** pass

The change targets the Collections list container directly, which is where row grouping and rounded-corner behavior are determined. It preserves existing swipe-to-delete and context-menu code paths for top, middle, and bottom rows.

### 2. Simplicity

**Result:** pass

The fix is a single modifier on the existing `List`. No new abstractions, helpers, or behavior branches were added.

### 3. No Scope Creep

**Result:** pass

Only the Library list styling and the task documentation were changed. No unrelated UI cleanup or list redesign was included.

### 4. Tests

**Result:** not applicable

This is a narrowly scoped SwiftUI presentation change on an existing private view composition point. No meaningful automated unit test surface exists for the rounded-corner interaction transition in the current test setup, so verification relied on build/install plus targeted code inspection.

### 5. Safety

**Result:** pass

The change is UI-only, adds no force unwraps, does not alter threading, and does not affect data mutation or delete behavior.

### 6. API Contract

**Result:** not applicable

No API or schema behavior changed.

### 7. Artifacts and Observability

**Result:** not applicable

The change does not touch recognition, detection, or debug artifact generation.

### 8. Static Analysis

**Result:** pass

The touched file passes targeted linting with `swiftlint lint apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/LibraryView.swift`. Repo-wide `make ios-lint` still fails, but only because of pre-existing SwiftLint violations outside this task in `RectangleFilter.swift`, `RecognitionQueueTests.swift`, `RectangleFilterTests.swift`, and `ScanYOLOSupportTests.swift`.

## Verification Results

- Baseline: `make ios-build` passed.
- Baseline: `make ios-lint` failed with pre-existing SwiftLint violations outside the touched files.
- Post-change: `make ios-build` passed.
- Post-change: `make ios-lint` failed with the same pre-existing SwiftLint violations.
- Post-change: `swiftlint lint apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/LibraryView.swift` passed.
- Post-change: installed and launched the built app in the iPhone 16 Pro simulator via `simctl`.

## Notes

- I could not perform a full interactive swipe/long-press visual check from this headless subagent session, so the verification is build-based plus targeted implementation inspection.
- The missing `docs/plans/collections-list-rounding-glitch.md` file referenced in the request context was not present in this worktree.
