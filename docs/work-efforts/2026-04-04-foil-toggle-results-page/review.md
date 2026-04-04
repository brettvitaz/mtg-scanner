# Review: Allow foil toggle on results page without duplicate guard

**Reviewed by:** opencode
**Date:** 2026-04-04

## Summary

**What was requested:** Remove the guard that prevents changing a card's foil state on the results page when the same card already exists in the opposite foil state, while preserving the guard for collections and decks.

**What was delivered:** Added `toggleFoilUnconditionally()` method to `CollectionItem`, updated `ResultsView` to use it for both single and bulk foil toggles, removed the unused conflict alert state and UI, and added two new tests.

**Deferred items:** none

## Code Review Checklist

### 1. Correctness

**Result:** pass

The code does exactly what was requested. `toggleFoil(_:)` and `toggleSelectedFoil()` now call `toggleFoilUnconditionally()` which always succeeds. The existing `toggleFoilIfNoDuplicate(in:)` and `hasFoilCollision(in:)` remain unchanged and are still used by collection/deck code paths.

### 2. Simplicity

**Result:** pass

`toggleFoilUnconditionally()` is a single-line method. `toggleFoil(_:)` is 3 lines. `toggleSelectedFoil()` is 6 lines. All well under 30 lines with no nesting. No unnecessary abstractions.

### 3. No Scope Creep

**Result:** pass

Only the requested changes were made. Removed dead code (unused alert state/UI) which is cleanup directly caused by the change. No unrelated modifications.

### 4. Tests

**Result:** pass

Two new tests added:
- `testToggleFoilUnconditionallyTogglesFoil` — verifies toggle works in both directions
- `testToggleFoilUnconditionallyIgnoresCollisions` — verifies the key behavior: no collision check

All 9 tests pass (7 existing + 2 new). Tests exercise real code paths and would fail if implementation were broken.

### 5. Safety

**Result:** pass

No force unwraps. No unhandled exceptions. Thread safety is correct — all changes are on @MainActor paths (SwiftUI View and SwiftData model). No secrets or sensitive data.

### 6. API Contract

**Result:** not applicable

No API contracts changed. This is purely client-side state management.

### 7. Artifacts and Observability

**Result:** pass

No debug artifacts affected. The haptic feedback (`UIImpactFeedbackGenerator`) is still called after toggle, preserving the tactile feedback signal.

### 8. Static Analysis

**Result:** pass

Build succeeded. All tests pass. No new lint violations introduced.

## Verification Results

Test verification:
```
xcodebuild test ... -only-testing:MTGScannerTests/CollectionItemFoilToggleTests
** TEST SUCCEEDED **
9 test cases passed (7 existing + 2 new)
```

Build verification:
```
xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build
** BUILD SUCCEEDED **
```

## Notes

The guard logic (`hasFoilCollision` / `toggleFoilIfNoDuplicate`) is preserved and still used by collection/deck merge logic. Only the results page bypasses it, which is the correct behavior since users may legitimately have both foil and non-foil copies of the same card in their inbox before moving them to a collection.
