# Request: Add Item Context Menu Actions

**Date:** 2026-04-03
**Author:** brettvitaz

## Goal

Add native press-and-hold actions for individual cards shown in Results, Collection Detail, and Deck Detail. Long press should expose copy, delete, and foil-toggle actions without breaking normal tap navigation, multi-select flows, or existing undo behavior.

## Requirements

1. Add a native `contextMenu` on item rows in Results, Collection Detail, and Deck Detail with `Copy`, `Delete`, and `Toggle Is Foil` actions.
2. Preserve normal tap-to-open behavior and do not show per-row context menus while explicit multi-select mode is active.
3. Reuse the existing copy sheet flow so copy destinations remain collections and decks.
4. Keep destructive delete behavior compatible with the app's shake-to-undo flow.
5. When toggling foil would create a duplicate sibling item in the same parent list, block the toggle and show lightweight user feedback instead of merging or duplicating rows.
6. Add test coverage for the nontrivial foil-toggle and undo behavior.

## Scope

**In scope:**
- Row actions for `CollectionItem` rows in Results, Collection Detail, and Deck Detail
- Shared UI support for the row context menu
- Foil-toggle collision protection for inbox, collections, and decks
- XCTest coverage for the new toggle and undo logic

**Out of scope:**
- Library-level collection and deck rows
- Schema or backend API changes
- New destination types for copy actions
- Unrelated project warnings or pre-existing lint failures outside this Swift work

## Verification

- `make ios-lint`
- `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`
- `xcodebuild test -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -destination 'platform=iOS Simulator,OS=18.6,name=iPhone 16' -only-testing:MTGScannerTests/CollectionModelsTests -only-testing:MTGScannerTests/CollectionItemFoilToggleTests -only-testing:MTGScannerTests/AppModelUndoTests`
- Manual checks:
  - Long press on an item row in Results, Collection Detail, and Deck Detail shows `Copy`, `Delete`, and `Toggle Is Foil`
  - Tap still opens card detail
  - Multi-select mode still behaves as before
  - Delete can be undone with shake and only the latest delete is restored
  - Foil toggle updates when unique and is blocked with feedback when it would collide

## Context

Files or docs the agent should read before starting:

- `apps/ios/MTGScanner/Features/Results/ResultsView.swift`
- `apps/ios/MTGScanner/Features/Library/CollectionDetailView.swift`
- `apps/ios/MTGScanner/Features/Library/DeckDetailView.swift`
- `apps/ios/MTGScanner/Features/Shared/CollectionItemRow.swift`
- `apps/ios/MTGScanner/Models/CollectionModels.swift`
- `apps/ios/MTGScanner/App/AppModel.swift`
- `apps/ios/MTGScanner/App/RootTabView.swift`
- `apps/ios/MTGScanner/Features/Shared/ShakeDetector.swift`
- `apps/ios/MTGScannerTests/CollectionModelsTests.swift`

## Notes

- Use a native iOS long-press context menu, not a custom confirmation dialog.
- Replace the old single-item long-press delete dialog flow rather than keeping both interactions in parallel.
