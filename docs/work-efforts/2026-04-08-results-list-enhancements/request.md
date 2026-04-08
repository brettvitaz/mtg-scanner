# Request: results list enhancements

**Date:** 2026-04-08
**Author:** Brett

## Goal

In the ios app,

- [x] add rarity to results list entries. it should be a circle with the color of the rarity and the letter. placement will be directly following the set name.
- [x] double tapping the results list entry will toggle foil state for the list entry.
- [x] add slide to delete for results, collections, and decks lists

## Requirements

1. Rarity circle: 18pt filled circle with rarity color (mythic=orange, rare=yellow, uncommon=gray, common=black/white adaptive) and white bold uppercase first letter. Common uses black circle/white text in light mode and white circle/black text in dark mode.
2. Double-tap foil toggle: Results tab only. Double-tapping a non-selecting-mode row toggles foil state with haptic feedback and triggers a price refetch.
3. Swipe-to-delete: Trailing swipe with full-swipe support in Results, CollectionDetail, and DeckDetail. Immediate delete (no confirmation alert) with undo support via shake gesture.

## Scope

**In scope:**
- `CollectionItemRow` rarity circle component and accessibility label update
- `ResultsView` double-tap gesture and swipe-to-delete
- `CollectionDetailView` swipe-to-delete
- `DeckDetailView` swipe-to-delete
- Structural refactors required to keep SwiftLint passing (extract `PriceFetchRequest`, move `bottomActionBar`/`actionButton` to extension)

**Out of scope:**
- Foil toggle in CollectionDetail or DeckDetail
- Rarity changes to CardDetailView or other views
- Any backend changes

## Verification

- `make ios-build` — confirms compilation
- `make ios-lint` — 0 violations
- Manual: rarity circle visible for all rarities, common circle adapts to color scheme, double-tap toggles foil icon + haptic, single-tap still navigates, swipe-to-delete works in all three views, undo restores deleted card

## Context

Files relevant to the implementation:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/CollectionItemRow.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Results/ResultsView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/CollectionDetailView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/DeckDetailView.swift`
