# ADR 0006: Validate Table-Scan Crops and Merge Split-Card Halves

## Status

Accepted

## Date

2026-04-30

## Context

The `tmp/table-scan-2` regression set exposed table/manual scan crop failures that were not covered by hinted auto-scan validation. Non-hinted multi-card cropping could return loose crops, overly aggressive crops, partial visible cards, or printed sub-rectangles. One split card (`IMG_1973`) was detected as two printed halves even though the user intent is one crop for the whole physical card.

The fix must stay inside the iOS crop pipeline. Recognition models, backend behavior, API contracts, schemas, and downstream recognition must remain unchanged.

## Decision

For non-hinted table/manual multi-card cropping:

- Evaluate each crop with the shared `CropQualityEvaluator` before returning crops.
- Treat under-crop and over-crop signals as hard rejection signals.
- Treat skew as a soft table-scan signal so slightly angled but complete table crops are not dropped.
- Preserve existing multi-card table behavior with a narrow two-complete-card fallback when one complete crop trips a lightweight quality flag.
- Merge narrow two-candidate split-card detections into one axis-aligned union crop when the candidate geometry indicates printed halves of the same physical card.
- Keep crop quality as a guardrail, not as a replacement for source-image fixtures with annotated ground-truth card geometry.

## Consequences

Positive:

- `IMG_1968`, `IMG_1969`, `IMG_1973`, `IMG_1979`, `IMG_1980`, and `IMG_1981` now have source-image regression coverage.
- Table/manual scans now reuse the same crop-quality machinery as hinted auto-scan, reducing validation drift.
- Split cards are protected against returning separate printed-half crops in the covered table-scan case.

Tradeoffs:

- The evaluator is intentionally lightweight and crop-only; it cannot reliably identify every semantic partial-card or missing-title crop.
- Some fallback behavior is deliberately conservative to avoid dropping complete cards from table layouts.
- Annotated source-image quads are still needed for stronger geometry assertions and less heuristic threshold tuning.
