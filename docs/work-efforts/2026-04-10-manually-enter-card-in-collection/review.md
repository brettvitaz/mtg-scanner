# Review: Manually enter card in collection

**Reviewed by:** claude-sonnet-4-6
**Date:** 2026-04-11

## Summary

**What was requested:** Allow users to manually search for and add a card to a collection or deck without scanning, via a three-stage modal flow backed by a new backend search endpoint.

**What was delivered:** Full three-stage modal flow (`AddCardView` / `AddCardViewModel`) with debounced name search, printing selection, and confirm screen; new `GET /api/v1/cards/search` endpoint; `finishes` field on `CardPrinting`; integration into `CollectionDetailView` and `DeckDetailView`; unit tests. Post-implementation addressed 5 PR review comments including a concurrency bug, a UI context bug, a no-op test, an API doc mismatch, and a DRY violation.

**Deferred items:** `lookup_by_set_and_number` multiple-match behavior (returns `None` for ambiguous set+number pairs) — acceptable for now since the method has no active callers.

## Code Review Checklist

### 1. Correctness

**Result:** pass

Three-stage flow correctly enforces the foil/non-foil constraint (disabled toggle for foil-only and non-foil-only printings). Race condition in `updateSearch` fixed: stale tasks cannot overwrite results after cancellation. `buildCollectionItem` correctly propagates quantity and foil from ViewModel state.

### 2. Simplicity

**Result:** pass

`AddCardViewModel` is 85 lines. `updateSearch` is 28 lines (function body). Views are structured as private computed properties and `@ViewBuilder` methods. No unnecessary abstractions. `fetchMissingPrices` consolidated from three copies to one on `AppModel`.

### 3. No Scope Creep

**Result:** pass

All changes are directly related to manual card entry or the PR review fixes. `ResultsView.fetchMissingPrices` was removed as part of the DRY fix (same duplication). No unrelated cleanup was performed.

### 4. Tests

**Result:** pass

`AddCardViewModelTests` covers `filteredPrintings` (6 cases), `buildCollectionItem` (2 cases), the `updateSearch` redundancy guard (now exercises the actual guard condition), and all `CardPrinting` finishes helpers (5 cases). `CollectionItemFromPrintingTests` covers the initializer. Tests would fail if implementations were removed.

### 5. Safety

**Result:** pass

No force unwraps in production code. `[weak self]` not needed (Tasks capture `self` weakly when `self` is `@Observable`). `@MainActor` correctly applied to `AddCardViewModel`. No secrets in code.

### 6. API Contract

**Result:** pass

New endpoint `GET /api/v1/cards/search` is additive. Existing endpoints (`/api/v1/cards/printings`, `/api/v1/recognitions`) are unchanged. Schema examples not affected.

### 7. Artifacts and Observability

**Result:** not applicable

No changes to recognition, detection, or artifact generation paths.

### 8. Static Analysis

**Result:** pass

`make api-lint` (mypy): clean — 21 source files, no issues.
`make ios-lint` (SwiftLint): 10 violations, all pre-existing in unchanged files (`CardDetectionEngine.swift`, `RectangleFilterTests.swift`, `AppModel.swift` line-length, etc.). No new violations introduced.

## Verification Results

```
make ios-build   → BUILD SUCCEEDED
make ios-test    → TEST SUCCEEDED (all AddCardViewModelTests pass)
make api-test    → 169 passed, 3 failed (pre-existing failures in test_llm_providers and test_recognitions, confirmed failing on master before this work)
make api-lint    → mypy: Success: no issues found in 21 source files
make ios-lint    → 10 violations, all pre-existing
```

## Notes

The 3 failing backend tests (`test_provider_uses_sensible_default_model`, `test_openai_provider_timeout_defaults_to_thirty_seconds`, `test_max_concurrent_recognitions_defaults_to_four`) are pre-existing and unrelated to this work effort. They fail identically on the master branch.
