# Plan: Manually enter card in collection

**Planned by:** claude-sonnet-4-6
**Date:** 2026-04-10

## Approach

Add a three-stage modal flow (`AddCardView`) driven by `AddCardViewModel` that covers name search (typeahead via new `/api/v1/cards/search` endpoint), printing selection (filterable by set/code/number), and a confirm screen (quantity stepper, foil toggle). Integrate it into `CollectionDetailView` and `DeckDetailView` via toolbar `+` buttons and empty-state buttons. Add a `finishes` field to `CardPrinting` to enable foil-only / non-foil-only detection.

## Implementation Steps

1. Add `search_names_by_prefix` to `MTGJSONIndex` and expose it via `GET /api/v1/cards/search` in the FastAPI router.
2. Add `finishes` to `CardPrinting`, expose `hasFoil`/`hasNonFoil`/`isFoilOnly`/`isNonFoilOnly` computed properties.
3. Implement `AddCardViewModel` with debounced search, printing fetch, and `buildCollectionItem`.
4. Implement `AddCardView` with three-stage navigation stack and all sub-views.
5. Wire `AddCardView` into `CollectionDetailView` and `DeckDetailView` with `.sheet` + toolbar/empty-state buttons.
6. Add `searchCardNames` and `fetchPrintings` to `APIClient` and `AppModel`.
7. Write unit tests for `AddCardViewModel` and `CollectionItem(from:)`.

Steps 1-2 are independent. Step 3 depends on step 2 for the finishes helpers. Steps 4-5 depend on step 3. Step 6 runs in parallel with 3-5.

## Files to Modify

| File | Change |
|------|--------|
| `services/api/app/services/mtgjson_index.py` | Add `search_names_by_prefix` and `lookup_by_set_and_number` |
| `services/api/app/api/routes/cards.py` | Add `GET /api/v1/cards/search` endpoint |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Models/RecognitionModels.swift` | Add `finishes` field to `CardPrinting` |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Models/CollectionModels.swift` | Add `CollectionItem(from:foil:quantity:)` initializer |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/APIClient.swift` | Add `searchCardNames` and `fetchPrintings` |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/AppModel.swift` | Expose search/printings/prices methods |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AddCard/AddCardViewModel.swift` | New file |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AddCard/AddCardView.swift` | New file |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/CollectionDetailView.swift` | Add sheet + trigger buttons |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/DeckDetailView.swift` | Add sheet + trigger buttons |

## Risks and Open Questions

- Collector number uniqueness: `set_code + collector_number` is not guaranteed unique in MTGJSON (language variants). `lookup_by_set_and_number` returns `None` for ambiguous matches — safe for now since the method is not yet called by any active feature.
- `fetchMissingPrices` will be duplicated across CollectionDetailView, DeckDetailView, and ResultsView until extracted to AppModel (deferred to post-PR cleanup).

## Verification Plan

- `make ios-build` — app compiles
- `make ios-test` — all unit tests pass
- `make api-test` — 169 tests pass (3 pre-existing failures excluded)
- `make api-lint` — mypy clean
- `make ios-lint` — SwiftLint: no new violations beyond pre-existing baseline
