# Request: Allow foil toggle on results page without duplicate guard

**Date:** 2026-04-04
**Author:** user

## Goal

Remove the guard that prevents changing a card's foil state on the results page when the same card already exists in the opposite foil state. Users should be able to have both foil and non-foil versions of the same card in their results.

## Requirements

1. Foil toggle on results page should always succeed, even if a duplicate exists with the opposite foil state
2. The guard logic should remain in place for collections and decks (only bypassed on results page)
3. Bulk foil toggle (multi-select) should also work without the guard
4. Remove the "Can't Toggle Is Foil" alert from the results page since it will no longer fire

## Scope

**In scope:**
- ResultsView.swift: change toggleFoil and toggleSelectedFoil to bypass the guard
- CollectionModels.swift: add an unconditional toggle method (or inline the toggle)
- Remove unused alert state and UI from ResultsView
- Add tests for the new unconditional toggle behavior

**Out of scope:**
- Changing the guard logic for collections or decks
- Any changes to how foil is handled elsewhere in the app

## Verification

- Run existing foil toggle tests: `xcodebuild test ... -only-testing:MTGScannerTests/CollectionItemFoilToggleTests`
- Build verification: `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`
- Lint: `make ios-lint`

## Context

- `apps/ios/MTGScanner/Features/Results/ResultsView.swift` — results page view, contains toggleFoil and toggleSelectedFoil
- `apps/ios/MTGScanner/Models/CollectionModels.swift` — CollectionItem model with hasFoilCollision and toggleFoilIfNoDuplicate
- `apps/ios/MTGScannerTests/CollectionItemFoilToggleTests.swift` — existing tests for foil toggle guard behavior

## Notes

The guard exists to prevent having two rows for the same card printing with different foil states in a collection or deck. On the results page (inbox), this is a valid use case — users may have scanned both foil and non-foil copies and want to track them separately before moving to a collection.
