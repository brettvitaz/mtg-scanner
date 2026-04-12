# Log: Manually enter card in collection

## Progress

### Step 1: Add backend search endpoint

**Status:** done

Added `search_names_by_prefix` to `MTGJSONIndex` supporting single-token prefix match and multi-token substring match. Exposed it via `GET /api/v1/cards/search` in `cards.py`. Added unit tests in `test_cards.py`.

Deviations from plan: none

---

### Step 2: Add finishes field to CardPrinting

**Status:** done

Added `finishes: String?` to `CardPrinting` with computed properties `hasFoil`, `hasNonFoil`, `isFoilOnly`, `isNonFoilOnly`. Nil finishes defaults to both foil and non-foil available.

Deviations from plan: none

---

### Step 3: Implement AddCardViewModel and AddCardView

**Status:** done

Implemented `AddCardViewModel` with debounced search (300ms), redundancy guard, printing fetch, and `buildCollectionItem`. Implemented `AddCardView` as a three-stage `NavigationStack` with name search, printing selection, and confirm screens. Added `PrintingRow` sub-view.

Deviations from plan: none

---

### Step 4: Wire into CollectionDetailView and DeckDetailView

**Status:** done

Added `showAddCard: Bool` state, `.sheet(isPresented:)` with `AddCardView`, toolbar `+` button, and empty-state "Add Card" button to both views.

Deviations from plan: none

---

### Step 5: Add APIClient and AppModel methods

**Status:** done

Added `searchCardNames` and `fetchPrintings` to `APIClient` and `AppModel`.

Deviations from plan: none

---

### Step 6: Write unit tests

**Status:** done

Added `AddCardViewModelTests` (filteredPrintings, buildCollectionItem, updateSearch redundancy guard, CardPrinting finishes helpers) and `CollectionItemFromPrintingTests`.

Deviations from plan: none

---

### Step 7: Address PR #67 review comments

**Status:** done

Addressed 5 actionable Copilot review comments from PR #67:

1. **Race condition in `updateSearch`** — Added `query == searchText` guards after each `await` point to prevent stale tasks from overwriting results or `isSearching`.
2. **Hard-coded "Add to Collection" title** — Added `confirmTitle: String` parameter to `AddCardView` (default `"Add to Collection"`); `DeckDetailView` passes `"Add to Deck"`.
3. **No-op redundancy guard test** — Made `lastSearchedQuery` and `searchTask` internal; rewrote test to actually call `updateSearch()` and assert `isSearching == false` and `searchTask == nil`.
4. **API param description mismatch** — Updated `q` description to reflect multi-token substring behavior.
5. **Duplicated `fetchMissingPrices`** — Extracted to `AppModel.fetchMissingPrices(for:)`; removed from `CollectionDetailView`, `DeckDetailView`, and `ResultsView`.

Deviations from plan: ResultsView was also updated (not originally in scope) since it had the same duplication. Net line change: -19 lines across the codebase.

---
