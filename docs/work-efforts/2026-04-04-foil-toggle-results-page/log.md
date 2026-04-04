# Log: Allow foil toggle on results page without duplicate guard

## Progress

### Step 1: Explored codebase to understand foil toggle and results page

**Status:** done

Read ResultsView.swift and CollectionModels.swift to understand the current foil toggle flow. Found that `toggleFoil(_:)` and `toggleSelectedFoil()` in ResultsView call `item.toggleFoilIfNoDuplicate(in: inboxItems)` which checks for collisions via `hasFoilCollision(in:)`. The guard blocks toggling if another inbox item with the same card (ignoring foil) already has the target foil state, showing an alert instead.

Deviations from plan: none

---

### Step 2: Added toggleFoilUnconditionally() to CollectionItem

**Status:** done

Added a new method `toggleFoilUnconditionally()` to CollectionModels.swift that simply calls `foil.toggle()` without any collision check. The existing `toggleFoilIfNoDuplicate(in:)` and `hasFoilCollision(in:)` methods remain unchanged for use by collections and decks.

Deviations from plan: none

---

### Step 3: Updated ResultsView to use unconditional toggle

**Status:** done

Changed `toggleFoil(_:)` to call `item.toggleFoilUnconditionally()` instead of the guarded version. Changed `toggleSelectedFoil()` to iterate and call `toggleFoilUnconditionally()` on each selected item, removing the skip counter and alert logic.

Deviations from plan: none

---

### Step 4: Removed unused alert state and UI from ResultsView

**Status:** done

Removed `showFoilConflictAlert` and `foilConflictMessage` @State properties since they are no longer referenced. Removed the `.alert("Can't Toggle Is Foil", ...)` modifier from the view body.

Deviations from plan: none

---

### Step 5: Added tests for toggleFoilUnconditionally()

**Status:** done

Added two test cases to CollectionItemFoilToggleTests.swift:
- `testToggleFoilUnconditionallyTogglesFoil` — verifies toggle works both directions
- `testToggleFoilUnconditionallyIgnoresCollisions` — verifies toggle succeeds even when a duplicate with opposite foil exists

Deviations from plan: none

---

### Step 6: Verified tests and build

**Status:** done

Ran `xcodebuild test ... -only-testing:MTGScannerTests/CollectionItemFoilToggleTests` — all 9 tests pass (7 existing + 2 new). Ran `xcodebuild ... build` — build succeeded.

Deviations from plan: none

---
