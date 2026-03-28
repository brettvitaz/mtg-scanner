# ADR-0002: Card Detection Approach

## Status
Accepted

## Context
The iOS app needs real-time card detection to locate MTG cards in the camera preview. The initial feature spec prescribed `VNDetectRectanglesRequest` (Apple Vision framework) for all detection modes. During implementation, rectangle detection proved insufficient for table mode — it struggled with overlapping cards, varied orientations, and low-contrast backgrounds (e.g., dark card art on dark surfaces).

Two distinct use cases emerged with different detection characteristics:
- **Table mode:** Cards scattered freely on a surface — variable count, orientation, overlap, and spacing.
- **Binder mode:** Cards in a regular 3x3 grid behind plastic sleeves — uniform spacing, predictable layout.

## Decision
Use a **dual-path detection strategy**:

- **Table mode:** `VNCoreMLRequest` with a trained YOLOv8n object detection model (`best.mlpackage`). The model was trained specifically on MTG card images and handles varied orientations, overlapping cards, and challenging backgrounds reliably.
- **Binder mode:** `VNDetectRectanglesRequest` to detect the binder page as a single large rectangle, then `GridInterpolator` (bilinear interpolation across the 4 page corners) to subdivide into a 3x3 grid. No trained model needed — the regular grid structure is exploitable geometrically.

Detection results are stabilized with `CardTracker`, which applies EMA (exponential moving average) smoothing on bounding box positions and presence hysteresis (appear/disappear thresholds) to prevent overlay flicker.

## Consequences
### Positive
- Table mode is accurate on real-world card photos with varied layouts.
- Binder mode is simple and deterministic — no model training needed for grid pages.
- EMA smoothing provides stable, non-flickery overlays at camera frame rate.
- The two paths share the same `DetectedCard` model and overlay rendering.

### Negative
- Requires shipping a Core ML model (~6 MB) in the app bundle.
- YOLO model needs retraining if detection requirements change significantly (e.g., different card sizes, non-MTG cards).
- Binder mode assumes a 3x3 grid; other layouts (2x2, 4x3) would need grid configuration.
