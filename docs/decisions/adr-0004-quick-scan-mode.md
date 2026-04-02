# ADR-0004: Quick Scan Mode Design

**Status:** Accepted  
**Date:** 2026-03-31  
**Author:** Quick Scan Feature Implementation

---

## Context

The MTG Scanner app allows users to recognize Magic: The Gathering cards by photographing them.  The existing scan modes (Table and Binder) require the user to manually tap a shutter button for each capture.  

A new use case emerged: a physical scanning station — a 3D-printed bin approximately the same shape as a Magic card, placed below the phone.  The user drops cards into the bin one at a time and expects the app to automatically detect and recognize each new card without any manual interaction.

The bin's geometry-based detection was ruled out immediately: because the bin is card-shaped, `VNDetectRectanglesRequest` would detect the bin walls as a "card" rectangle, producing false positives on every frame regardless of whether an actual card is present.

---

## Decision

### Detection Strategy: YOLO + Frame Differencing

Two signals are combined to determine when a **new** card has been placed:

1. **YOLO object detection** (`YOLOCardDetector`)  
   Uses the bundled `MTGCardDetector.mlmodelc` — a YOLOv8n model trained on the Roboflow Magic Card Detection Dataset 2 (1.1 k images, single class: "card").  The model produces raw detection tensors (`var_909`, shape `[1, 5, 8400]`) without built-in NMS.  Post-processing (greedy NMS with IoU threshold 0.45) is applied on-device.  
   - Confirms a card **object** is visible, distinguishing it from bin geometry.

2. **Frame differencing** (`FrameDifferenceAnalyzer`, `CardPresenceTracker`)  
   Sparse luminance sampling (every 16 px) of the BGRA pixel buffer is compared against a reference sample taken immediately after the last capture.  A normalized MAD (mean absolute difference) above a configurable threshold (default 3%) signals that the scene has changed — i.e., a new card was dropped.
   - Prevents re-triggering on the same card that is already in the bin.

A "new card" event fires only when both YOLO and frame differencing agree.  This combination avoids:
- Spurious triggers when the bin is empty (frame diff high from ambient movement but YOLO sees no card)  
- Re-triggering on the same card (YOLO sees card but frame diff is below threshold vs. captured reference)

### State Machine

```
watching  ─── (new card signal) ──► settling
settling  ─── (settle timer fires) ──► capturing ──► watching
settling  ─── (new signal during settle) ──► settling (timer continues)
```

The settle timer (configurable 0.5 – 5.0 s, default 2.0 s) gives the card time to stop moving after being dropped.  Capturing while the card is still in motion would produce blurry or partially occluded images.

Capturing and recognition happen entirely asynchronously: the state returns to `.watching` immediately after enqueuing the image, so the next card can be dropped without waiting for API results.

### Recognition Queue

`RecognitionQueue` manages async recognition:
- Up to `maxConcurrent` (default 2) simultaneous API calls to avoid overwhelming the server.
- Each job is retried once on failure before being marked failed.
- Results are persisted directly to SwiftData (`CollectionItem`) without going through `AppModel`, keeping the quick-scan path independent.
- Published counts (`pendingCount`, `completedCount`, `failedCount`) drive the UI without coupling to the main recognition flow.

No backend changes were needed: the existing `POST /api/v1/recognitions` endpoint is sufficient.

### UI Integration

Quick Scan is integrated as a third `DetectionMode` (`.quickScan`) rather than a separate tab or screen.  Reasons:
- The camera pipeline is identical — same `CameraSessionManager`, `CameraViewController`, `CardDetectionEngine`.
- Mode switching is already a first-class concept in the UI.
- `DetectionMode.quickScan` is only visible in the mode picker when `quickScanEnabled` is `true` in Settings, preventing confusion for users who don't use the feature.

When the mode is `.quickScan`, `ScanView` renders `QuickScanView` as an overlay instead of the standard shutter / photo picker controls.

### Model Reuse vs. Retraining

The existing model (`tmp/mtg.mlpackage`, ~5.9 MB) was used without modification.  Retraining was deferred because:
- The scanning station provides a controlled, top-down view that should match the model's training distribution closely.
- Confidence threshold (0.3 – 0.9, configurable) provides a runtime tuning knob without rebuilding the model.
- Initial inference results on-device can be evaluated before investing in a new training run.

---

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| VNDetectRectanglesRequest | The bin is card-shaped; would produce constant false positives |
| Single signal (YOLO only) | Cannot distinguish a new card from the same card already in the bin |
| Single signal (frame diff only) | Cannot confirm a card (not just hands/ambient motion) is present |
| Separate tab for Quick Scan | Duplicates camera setup; inconsistent with existing mode-switching UX |
| New trained model for scanning station | Deferred; existing model expected to be sufficient for constrained environment |

---

## Consequences

- **Positive:** Hands-free scanning — drop cards one at a time without tapping the screen.
- **Positive:** No backend changes required; fully additive feature.
- **Positive:** Confidence threshold and settle delay are user-configurable via Settings.
- **Neutral:** Runs two Vision requests per frame in Quick Scan mode (YOLO in `CardDetectionEngine` for the overlay + YOLO in `CardPresenceTracker` for the state machine).  On A-series chips this is well within frame budget.
- **Negative:** Requires the bundled `MTGCardDetector.mlmodelc` (~5.9 MB) in the app bundle; this increases app size.
- **Future:** If detection accuracy is insufficient for different lighting or card back styles, a new YOLOv8n model trained specifically on top-down bin images should replace the current model.
