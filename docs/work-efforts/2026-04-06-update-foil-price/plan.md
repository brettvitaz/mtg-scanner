# Plan: Update price when changing foil status from results screen

**Planned by:** opencode
**Date:** 2026-04-06

## Approach

Add a `refetchPrice(for:)` helper to `ResultsView` that fetches the price for a card's current foil status. Call it after each foil toggle — once for single toggles, and in parallel via `TaskGroup` for bulk toggles. Capture the requested foil state before each async call and skip applying results if `item.foil` changed, preventing stale responses from overwriting the current price.

## Implementation Steps

1. Add `refetchPrice(for:)` helper that captures `item.foil` before the async fetch and validates it hasn't changed before applying the result.
2. Update `toggleFoil(_:)` to call `Task { await refetchPrice(for: item) }` after toggling.
3. Update `toggleSelectedFoil()` to extract fetch-safe values (id, name, scryfallId, isFoil) before the TaskGroup, run all price fetches in parallel, and apply results only if `item.foil` still matches the requested state.
4. Verify with `make ios-build`, `make ios-lint`, and `make ios-test`.

All steps are sequential — each builds on the previous.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Results/ResultsView.swift` | Add `refetchPrice` helper, update `toggleFoil` and `toggleSelectedFoil` to re-fetch prices with stale-response guards |

## Risks and Open Questions

- `CollectionItem` is a `@Model` (main actor-isolated) and cannot be captured in `sending` closures inside `TaskGroup`. Need to extract primitive values before the concurrent block.
- If the user toggles foil rapidly, multiple in-flight requests could complete out of order. Mitigated by capturing and checking `requestedFoil` before applying results.

## Verification Plan

- `make ios-build` — compiles without errors
- `make ios-lint` — no SwiftLint violations
- `make ios-test` — all tests pass
- Manual: toggle foil on a card with known foil/non-foil price difference, confirm price updates correctly
