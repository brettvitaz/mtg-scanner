# ADR 0005: Validate Hinted Auto-Scan Crops Before Returning Them

## Status

Accepted

## Date

2026-04-30

## Context

Auto-scan still captures use a YOLO box as the best available whole-card location, then Vision rectangle detection refines the final crop. Regression fixtures `IMG_1955`, `IMG_1956`, `IMG_1957`, and `IMG_1960` showed that Vision can rank printed card internals higher than the physical card boundary. The previous single-crop path returned the top-ranked Vision crop immediately, which made severe interior text-box crops possible.

The crop service needs to preserve the existing response contract and avoid backend/model changes. It also needs to keep manual/table scan behavior compatible unless a YOLO hint is present.

## Decision

For hinted auto-scan cropping:

- Rank eligible Vision candidates, but do not return the first candidate blindly.
- Validate each perspective-corrected candidate with lightweight crop-quality metrics before returning it.
- Reject candidates that are too small relative to the YOLO hint or have poor hint support.
- Reject crops whose edge/background metrics indicate an under-crop and crops whose printed layout remains visibly skewed.
- If no Vision candidate passes validation, return the YOLO axis-aligned crop rather than a bad Vision interior crop.

Manual/table scan paths without a hint continue to use existing filter/ranking behavior.

## Consequences

Positive:

- Auto-scan no longer commits to obvious printed-interior rectangles before validation.
- The fallback behavior prefers a whole-card crop, even if less geometrically refined, over a perspective-corrected crop fragment.
- Tests and production share the same core crop-quality evaluator, reducing test/production drift.

Tradeoffs:

- YOLO fallback crops may include more background and perspective skew than an ideal Vision crop.
- Lightweight image metrics can reject or accept borderline cases; they should be treated as guardrails.
- Future source-image fixtures with annotated card quads are still needed for stronger geometry regression tests.
