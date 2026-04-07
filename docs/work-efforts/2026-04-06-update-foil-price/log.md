# Log: Update price when changing foil status from results screen

## Progress

Append a new step section each time you complete a meaningful unit of work.
Use the format below. Do not use tables — headings and paragraphs are easier to maintain.

### Step 1: Initial exploration and planning

**Status:** done

Explored the codebase to understand how the results screen, foil toggle, and price fetching work. Key findings: `toggleFoilUnconditionally()` is called without any price update; `fetchMissingPrices` only runs on initial load; the backend `GET /api/v1/cards/price` endpoint already accepts `is_foil`. Created the plan in `plan.md`.

Deviations from plan: none

---

### Step 2: Implement refetchPrice helper and update toggleFoil

**Status:** done

Added `refetchPrice(for:)` helper that captures `item.foil` before the async fetch and validates it hasn't changed before applying results. Updated `toggleFoil(_:)` to call `Task { await refetchPrice(for: item) }` after toggling.

Deviations from plan: none

---

### Step 3: Implement bulk toggle with parallel price fetches

**Status:** done

Updated `toggleSelectedFoil()` to extract fetch-safe values (id, name, scryfallId, isFoil) before the `TaskGroup`, run all price fetches in parallel, and apply results only if `item.foil` still matches the requested state. This avoids capturing `CollectionItem` in `sending` closures (main actor isolation violation).

Deviations from plan: none

---

### Step 4: Fix Swift concurrency error

**Status:** done

Initial build failed with "passing closure as a 'sending' parameter risks causing data races" because `CollectionItem` is main actor-isolated. Fixed by extracting primitive values into a `fetchRequests` array before the `TaskGroup`, then matching results back to items by ID.

Deviations from plan: none

---

### Step 5: Fix stale response race condition (code review)

**Status:** done

Code review identified that rapid foil toggles could cause stale async responses to overwrite the current price. Fixed by: (1) capturing `requestedFoil` in `refetchPrice` and skipping assignment if `item.foil` changed, (2) checking `item.foil` against the captured `isFoil` in the bulk toggle result application.

Deviations from plan: none

---

### Step 6: Verify build, lint, and tests

**Status:** done

Ran `make ios-build` — BUILD SUCCEEDED. Ran `make ios-lint` — 0 violations. Ran `make ios-test` — TEST SUCCEEDED.

Deviations from plan: none

---
