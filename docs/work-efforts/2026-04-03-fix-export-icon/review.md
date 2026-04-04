# Review: Fix export icon

**Reviewed by:** opencode
**Date:** 2026-04-03

## Summary

**What was requested:** Replace the `...` (ellipsis.circle) export icon with the Apple share icon (square.and.arrow.up).

**What was delivered:** Replaced `Image(systemName: "ellipsis.circle")` with `Image(systemName: "square.and.arrow.up")` in all three detail views (ResultsView, CollectionDetailView, DeckDetailView), 6 occurrences total.

**Deferred items:** none

## Code Review Checklist

### 1. Correctness

**Result:** pass

All six occurrences of `ellipsis.circle` replaced with `square.and.arrow.up`. Grep confirms zero remaining `ellipsis.circle` references in the codebase. The change is purely cosmetic — the Menu structure, ExportMenuContent, and sheet presentation are untouched.

### 2. Simplicity

**Result:** pass

Single-line SF Symbol name changes. No new functions, abstractions, or nesting introduced.

### 3. No Scope Creep

**Result:** pass

Only the three specified files were modified. No unrelated changes.

### 4. Tests

**Result:** pass | not applicable

No logic changed — only a visual icon name swap. Existing ExportServiceTests cover export functionality which is unaffected. No new tests needed.

### 5. Safety

**Result:** pass

No force unwraps, no exception handling changes, no threading impact. The `square.and.arrow.up` SF Symbol is available on all supported iOS versions.

### 6. API Contract

**Result:** not applicable

No API changes.

### 7. Artifacts and Observability

**Result:** not applicable

No impact on debug artifacts or logging.

### 8. Static Analysis

**Result:** pass

`make ios-lint` — 0 violations across 69 files. `xcodebuild` debug build succeeded.

## Verification Results

- `make ios-lint`: 0 violations, 0 serious in 69 files
- `xcodebuild` debug build: BUILD SUCCEEDED
- `grep -r "ellipsis.circle"` in apps/ios: no matches (all replaced)

## Notes

none
