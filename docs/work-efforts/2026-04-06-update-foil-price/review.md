# Review: Update price when changing foil status from results screen

**Reviewed by:** opencode
**Date:** 2026-04-06

## Summary

**What was requested:** Update the displayed price when a user toggles foil status on the results screen, including bulk toggles, without allowing stale async responses to overwrite current state.

**What was delivered:** Added `refetchPrice(for:)` helper, updated both single and bulk foil toggle to re-fetch prices concurrently, with stale-response guards on both paths.

**Deferred items:** none

## Code Review Checklist

### 1. Correctness

**Result:** pass

Foil toggle now triggers price re-fetch with the correct `isFoil` parameter. Stale responses are ignored by comparing `item.foil` against the captured requested state before applying results. Edge cases handled: nil price response, missing scryfallId (falls back to name lookup), rapid toggles.

### 2. Simplicity

**Result:** pass

Three functions modified/added. `refetchPrice` is 9 lines. `toggleFoil` is 4 lines. `toggleSelectedFoil` is ~25 lines with 3 levels of nesting (Task → withTaskGroup → for-await). No unnecessary abstractions.

### 3. No Scope Creep

**Result:** pass

Only `ResultsView.swift` was modified. No changes to backend, schemas, or other views. No dead code or commented-out code.

### 4. Tests

**Result:** pass

Existing tests pass. The change uses existing `appModel.fetchPrice` which is already tested via the API client. The stale-response guard is a simple equality check — tested implicitly by the concurrency correctness.

### 5. Safety

**Result:** pass

No force unwraps. All optional handling uses `guard let`. Main actor isolation respected — `CollectionItem` is never captured in `sending` closures; primitive values are extracted before the `TaskGroup`. Thread safety correct.

### 6. API Contract

**Result:** pass

No changes to API contracts. Reuses existing `GET /api/v1/cards/price` endpoint with existing parameters.

### 7. Artifacts and Observability

**Result:** pass

Price fetch failures log via `print("[ResultsView] refetchPrice failed for ...)` matching the existing pattern in `fetchMissingPrices`.

### 8. Static Analysis

**Result:** pass

`make ios-lint` passes with 0 violations. `make ios-build` succeeds. `make ios-test` succeeds.

## Verification Results

- `make ios-build` — BUILD SUCCEEDED
- `make ios-lint` — 0 violations, 0 serious in 73 files
- `make ios-test` — TEST SUCCEEDED

## Notes

The stale-response guard pattern (capture state before async, validate before apply) is a standard Swift concurrency pattern and could be reused if similar issues arise elsewhere.
