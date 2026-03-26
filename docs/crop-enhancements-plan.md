# Crop Enhancements Plan

## Problem
The current multi-card crop detector works on simple multi-card shots but fails badly on a binder page full of MTG cards. On the sample image `samples/test/binder_page_1.jpg`, it currently detects only 2 cards when the expected result is 9.

## Goal
Improve server-side card detection/cropping in `services/api` so a 3x3 binder page is detected as 9 individual card regions, while preserving current behavior for existing single-card and simple two-card inputs.

## Findings from baseline
- Current detector relies mostly on external contours from edge/background masks.
- On the binder-page sample, those masks merge or miss most neighboring pockets/cards.
- The current implementation successfully finds only the left-column cards in the sample.
- Existing regression coverage includes a real two-card sample but not a dense binder-page layout.

## Proposed approach
1. Keep the existing contour-based detector as one signal source.
2. Add a second candidate-generation path tuned for dense repeated layouts:
   - derive an adaptive/local-contrast mask in addition to the current edge/background masks
   - use contour retrieval that can see more interior rectangular structures, not only large externals
   - keep plausible card-shaped rectangles across a bounded area range
3. For dense binder-style layouts, add a lightweight grid-completion pass:
   - infer row/column centers from consistent card candidates
   - preserve the strongest real detections
   - synthesize only the missing grid slots when the layout cleanly resolves to a 3x3 pattern
4. Merge candidates from all sources.
5. Keep overlap suppression, but dedupe only true duplicates so adjacent binder pockets survive.
6. Add binder-page regression tests that require 9 detections on `binder_page_1.jpg`.
7. Verify current real two-card regression still passes.

## Implementation steps
1. Reproduce current failure in tests/scripts.
2. Extend `CardDetector` candidate-mask generation for dense binder-page inputs.
3. Adjust candidate extraction/filtering if needed so valid card rectangles are retained.
4. Add regression tests for the binder-page sample.
5. Run focused API tests.
6. Commit only the feature changes.

## Acceptance criteria
- `binder_page_1.jpg` produces exactly 9 detected regions.
- Existing two-card real-sample regression still passes.
- Crop generation still works for detected regions.
- `services/api/tests/test_multi_card.py` passes.
