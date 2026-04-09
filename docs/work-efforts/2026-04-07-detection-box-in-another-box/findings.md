# Findings: Detection box inside another box

**Date:** 2026-04-09
**Author:** Codex

## Goal

In scan mode, surface one overlay per real card, suppress nested card-feature rectangles that appear inside a real card, preserve valid peer cards in multi-card scenes, and avoid applying stale YOLO validation state after a mode or orientation change.

## Findings

1. Confidence order is the wrong decision rule for containment.

The rejected fixes still let a higher-confidence inner rectangle beat a lower-confidence enclosing card because containment suppression ran greedily over a confidence-sorted list. That is exactly the wrong optimization target for this bug: inner boxes are usually card features, not better card detections.

2. A larger enclosing box is not always correct either.

Some large boxes are real single-card candidates, but some are aggregate boxes that span multiple separate cards. A correct algorithm must distinguish "one card enclosing a feature box" from "one loose box enclosing multiple peer cards."

3. The previous tests reinforced the wrong behavior.

One of the existing rectangle tests asserted that a tighter higher-confidence inner box should win over an enclosing outer box. That expectation conflicts with the product goal and made reviewer-rejected fixes look acceptable in CI.

4. Scan-YOLO cache reset ordering was racy.

`updateDetectionMode` and `updateIsLandscape` published new state immediately, but the scan-YOLO cache reset happened later on `visionQueue`. A frame captured just after the change could therefore be processed under the new configuration while still consuming cached YOLO boxes from the old one.

5. The final implementation now protects the two main invariants in tests.

Focused tests now prove that a higher-confidence inner feature box does not beat an enclosing card, that the result does not depend on input order, that containment chains collapse to the outermost single-card candidate, and that stale YOLO cache generations are ignored after mode/orientation changes.

6. The remaining uncertainty is scene realism, not basic algorithm correctness.

The current fix closes the logical holes that kept getting flagged in review, but the aggregate-container rule and the existing geometric thresholds are still heuristics. The remaining risk is that some real camera scenes may need threshold tuning or additional scene coverage, not that the algorithm is still choosing winners by the wrong rule.

## Correct Algorithm

At a high level, the scan-mode pipeline should work like this:

1. Filter raw rectangles by confidence and card-like aspect ratio.
2. Run IoU-based non-maximum suppression to remove near-duplicate rectangles. Confidence is appropriate here because this is a duplicate-selection problem.
3. Build containment relationships across the full set of NMS survivors. Do not decide containment greedily in confidence order.
4. Classify any rectangle with multiple direct contained children as an aggregate outer box and reject it so peer cards are preserved.
5. For the remaining non-aggregate rectangles, suppress any rectangle that has a non-aggregate ancestor. This makes the enclosing single-card candidate win over nested feature boxes and collapses containment chains to the outermost real card.
6. Validate the surviving scan rectangles against cached YOLO results, but tie the YOLO cache generation to the same serialized mode/orientation changes that govern frame processing.

## Risks and Trade-offs

- The containment algorithm is more complex than a one-pass greedy filter, but the extra structure is necessary to distinguish nested-feature scenes from multi-card scenes.
- Aggregate-box detection is still heuristic. The direct-child rule is a practical choice, but it could need tuning if real camera input produces unusual containment patterns.
- Synchronous state updates on `visionQueue` improve correctness and determinism, but they make mode/orientation changes wait for queue serialization instead of being fire-and-forget.
- Threshold tuning may still be required on live preview data, but threshold changes should not change the core invariants above: confidence must not decide nested-box winners, and stale cache contents must not survive configuration changes.

## Future Work

1. Run live preview validation against the scenes that originally triggered the bug, especially:
   - one real card with strong internal rectangular artwork/text regions;
   - two or more adjacent cards where a loose outer aggregate box is plausible;
   - immediate mode switches and device rotations while scan mode is active.
2. If live validation still shows false positives or missed cards, tune containment, IoU, coverage, TTL, and stride thresholds without changing the core selection invariants.
3. Capture at least a small corpus of representative rectangle/YOLO snapshots from real scans and turn the most failure-prone cases into regression fixtures so future refactors are not judged only on synthetic geometry tests.
4. If aggregate-box heuristics remain unstable in production scenes, consider enriching containment classification with additional evidence already available in the pipeline, such as corner quality, rectangle geometry consistency, or YOLO support strength, instead of falling back to confidence order.
