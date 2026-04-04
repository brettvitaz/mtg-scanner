# Plan: Allow foil toggle on results page without duplicate guard

**Planned by:** opencode
**Date:** 2026-04-04

## Approach

Add a new `toggleFoilUnconditionally()` method to `CollectionItem` that toggles foil without checking for collisions. Update `ResultsView` to use this method instead of `toggleFoilIfNoDuplicate(in:)`, and remove the now-unused alert state and UI. The existing guard logic remains intact for collections and decks.

## Implementation Steps

1. Add `toggleFoilUnconditionally()` to `CollectionItem` in `CollectionModels.swift` — simple method that just calls `foil.toggle()`
2. Update `toggleFoil(_:)` in `ResultsView.swift` to call `toggleFoilUnconditionally()` instead of the guarded version
3. Update `toggleSelectedFoil()` in `ResultsView.swift` to call `toggleFoilUnconditionally()` and remove the skip/alert logic
4. Remove `showFoilConflictAlert`, `foilConflictMessage` state and the associated alert UI from `ResultsView`
5. Add tests for `toggleFoilUnconditionally()` in `CollectionItemFoilToggleTests.swift`
6. Run tests and build to verify

Step 1 is independent. Steps 2-4 depend on step 1. Step 5 can be done after step 1. Step 6 depends on all prior steps.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScanner/Models/CollectionModels.swift` | Add `toggleFoilUnconditionally()` method |
| `apps/ios/MTGScanner/Features/Results/ResultsView.swift` | Use unconditional toggle, remove alert state/UI |
| `apps/ios/MTGScannerTests/CollectionItemFoilToggleTests.swift` | Add tests for new method |

## Risks and Open Questions

- None. The change is straightforward and the guard logic is preserved for other use cases.

## Verification Plan

- `xcodebuild test ... -only-testing:MTGScannerTests/CollectionItemFoilToggleTests` — all existing tests pass plus new tests
- `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build` — build succeeds
- `make ios-lint` — no new lint violations
