# Log: results list enhancements

## Progress

### Step 1: Add RarityCircle to CollectionItemRow

**Status:** done

Added `RarityCircle` private struct to `CollectionItemRow.swift`. Wrapped the edition `Text` in an `HStack` with `RarityCircle` guarded by `if let rarity = item.rarity, !rarity.isEmpty`. Updated `accessibilitySummary` to include rarity. Colors: mythic=orange, rare=yellow, uncommon=gray, common=adaptive (see step 5).

Deviations from plan: none

---

### Step 2: Add double-tap foil toggle to ResultsView

**Status:** done

Added `.simultaneousGesture(TapGesture(count: 2).onEnded { toggleFoil(item) })` on the `NavigationLink` in `ResultsView.cardRowView(for:)`. This coexists with the single-tap navigation link. Only applies in non-selecting mode (selecting branch renders without `NavigationLink`).

Deviations from plan: none

---

### Step 3: Add swipe-to-delete to ResultsView

**Status:** done

Added `.swipeActions(edge: .trailing, allowsFullSwipe: true)` with a destructive `Button` calling `deleteItem(_:)` on the `NavigationLink` in `ResultsView.cardRowView(for:)`. Uses existing `deleteItem` which handles haptic feedback and undo registration.

Deviations from plan: none

---

### Step 4: Extract PriceFetchRequest to its own file

**Status:** done

`PriceFetchRequest` struct moved from `ResultsView.swift` to new file `Features/Results/PriceFetchRequest.swift`. Required to satisfy SwiftLint `file_length` rule (file was 410 lines, limit is 400). Structural fix — the type has no view dependencies.

Deviations from plan: This was a required structural fix discovered during lint verification, not a cosmetic compaction.

---

### Step 5: Add swipe-to-delete to CollectionDetailView

**Status:** done

Added `.swipeActions(edge: .trailing, allowsFullSwipe: true)` on the `NavigationLink` in `CollectionDetailView.cardRowView(for:)`. Calls existing `deleteItem(_:)`.

Deviations from plan: none

---

### Step 6: Add swipe-to-delete to DeckDetailView

**Status:** done

Added `.swipeActions(edge: .trailing, allowsFullSwipe: true)` on the `NavigationLink` in `DeckDetailView.cardRowView(for:)`. Calls existing `deleteItem(_:)`.

Deviations from plan: none

---

### Step 7: Move DeckDetailView helpers to private extension

**Status:** done

Moved `bottomActionBar` computed property and `actionButton` helper method from the `DeckDetailView` struct body to a `private extension DeckDetailView`. Required to satisfy SwiftLint `type_body_length` rule (struct body was 203 non-comment lines, limit is 200). Structural fix — these helpers are logically a separate concern (bottom action bar UI).

Deviations from plan: This was a required structural fix discovered during lint verification.

---

### Step 8: Adapt common rarity circle for dark/light mode

**Status:** done

Updated `RarityCircle` to use `@Environment(\.colorScheme)`. Common rarity: black circle with white text in light mode; white circle with black text in dark mode. Added `isCommon` computed property and split background/text color into separate properties.

Deviations from plan: Initial implementation used `Color.secondary` for common. Updated after user feedback to use explicit adaptive colors.

---

### Step 9: Build and lint verification

**Status:** done

`make ios-build` — BUILD SUCCEEDED. `make ios-lint` — 0 violations, 0 serious in 77 files.

Deviations from plan: none
