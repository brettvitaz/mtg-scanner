# Request: Update price when changing foil status from results screen

**Date:** 2026-04-06
**Author:** User

## Goal

When a user toggles the foil status of a card on the results screen, the displayed price should update to reflect the foil or non-foil price from the backend.

## Requirements

1. Toggling foil on a single card (via context menu) must re-fetch and update the price.
2. Bulk toggling foil on multiple selected cards must re-fetch and update all prices concurrently.
3. Stale async responses must not overwrite the price if the user toggles foil again before the previous request completes.

## Scope

**In scope:**
- iOS client-side changes to `ResultsView.swift`
- Reusing existing `GET /api/v1/cards/price` endpoint (no backend changes needed)

**Out of scope:**
- Backend API changes
- Price updates in Collection or Deck views (only Results screen)

## Verification

- `make ios-build` passes
- `make ios-lint` passes
- `make ios-test` passes
- Manual test: toggle foil on a card with known price difference, verify price updates

## Context

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Results/ResultsView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Models/CollectionModels.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/APIClient.swift`
- `services/api/app/api/routes/cards.py` — existing price endpoint already accepts `is_foil` parameter

## Notes

The existing `fetchMissingPrices` only runs on initial load and skips cards that already have prices. The foil toggle currently calls `toggleFoilUnconditionally()` without any price update.
