# Request: Manually enter card in collection

**Date:** 2026-04-10
**Author:** bvitaz

## Goal

Allow users to manually search for and add a Magic: The Gathering card to a collection or deck without scanning. The flow should support searching by name, selecting a specific printing (edition), and configuring quantity and foil status before adding.

## Requirements

1. Provide a searchable card name lookup backed by the MTGJSON index.
2. Allow the user to select a specific printing (set, collector number) for the chosen card name.
3. Let the user configure quantity and foil before confirming the add.
4. Integrate the flow into both CollectionDetailView and DeckDetailView via a "+" button and empty-state trigger.
5. Support foil-only and non-foil-only printings by disabling the toggle when appropriate.

## Scope

**In scope:**
- iOS UI: three-stage modal flow (name search → printing selection → confirm & add)
- Backend API: `/api/v1/cards/search` endpoint for card name prefix/multi-token search
- Model updates: `finishes` field on `CardPrinting` for foil-only detection
- Integration: `+` buttons and empty-state add triggers in CollectionDetailView and DeckDetailView

**Out of scope:**
- Bulk import or CSV entry
- Editing or removing existing collection items
- Changes to the scanning or recognition flow

## Verification

- `make ios-build` passes
- `make ios-test` passes
- `make api-test` passes (pre-existing failures excluded)
- Manual: tap `+` in a collection, search "Lightning Bolt", select a printing, set quantity/foil, confirm — card appears in the list

## Context

Files or docs the agent should read before starting:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/CollectionDetailView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/DeckDetailView.swift`
- `services/api/app/services/mtgjson_index.py`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Models/CollectionModels.swift`
