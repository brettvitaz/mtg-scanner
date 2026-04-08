# Plan: results list enhancements

**Planned by:** Claude Sonnet 4.6
**Date:** 2026-04-08

## Approach

Add a rarity circle indicator to `CollectionItemRow` (shared component), a double-tap-to-toggle-foil gesture to `ResultsView`, and swipe-to-delete to all three card list views. The rarity circle is a private struct within `CollectionItemRow.swift` using `@Environment(\.colorScheme)` to adapt common's colors. The double-tap uses `.simultaneousGesture` to coexist with the `NavigationLink` single-tap. Swipe-to-delete uses `.swipeActions` (no edit mode required) calling the existing `deleteItem` method which already handles haptic and undo.

## Implementation Steps

1. **`CollectionItemRow.swift`** — add `RarityCircle` private struct; wrap edition `Text` in an `HStack` with `RarityCircle`; update `accessibilitySummary` to include rarity.
2. **`ResultsView.swift`** — add `.simultaneousGesture(TapGesture(count: 2))` and `.swipeActions` to the `NavigationLink` in `cardRowView(for:)`. Extract `PriceFetchRequest` to its own file to satisfy SwiftLint `file_length` rule (structural fix, not cosmetic).
3. **`PriceFetchRequest.swift`** (new) — standalone data type extracted from `ResultsView.swift`.
4. **`CollectionDetailView.swift`** — add `.swipeActions` to `NavigationLink` in `cardRowView(for:)`.
5. **`DeckDetailView.swift`** — add `.swipeActions` to `NavigationLink` in `cardRowView(for:)`. Move `bottomActionBar` and `actionButton` to `private extension DeckDetailView` to satisfy SwiftLint `type_body_length` rule (structural fix).

Steps 1–5 are independent and can be done in any order. Step 3 must precede finalizing step 2 (removes the type from that file).

## Files to Modify

| File | Change |
|------|--------|
| `Features/Shared/CollectionItemRow.swift` | Add `RarityCircle`, inline after edition text, update accessibility |
| `Features/Results/ResultsView.swift` | Double-tap gesture, swipe-to-delete, remove `PriceFetchRequest` |
| `Features/Results/PriceFetchRequest.swift` | New file — extracted struct |
| `Features/Library/CollectionDetailView.swift` | Swipe-to-delete |
| `Features/Library/DeckDetailView.swift` | Swipe-to-delete, move helpers to extension |

## Risks and Open Questions

- `.simultaneousGesture` with double-tap may fire the foil toggle on the second tap of a fast double-tap-then-navigate sequence — acceptable UX tradeoff given Results-tab-only scope.
- `RarityCircle` uses `Color.secondary` as fallback for unknown rarities; this will appear as a gray circle, which is reasonable.
- Common rarity color is adaptive (dark/light mode) — verified manually.

## Verification Plan

```bash
make ios-build   # confirms compilation
make ios-lint    # 0 violations across all files
```

Manual checks:
- Rarity circle renders for mythic, rare, uncommon, common, nil/empty (absent)
- Common circle: black bg + white text in light mode; white bg + black text in dark mode
- Double-tap toggles foil sparkle + haptic in Results only
- Single-tap still navigates to CardDetailView
- Swipe-to-delete in Results, CollectionDetail, DeckDetail
- Full swipe triggers immediate delete
- Shake to undo restores card
- Selection mode unaffected
