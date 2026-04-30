# Plan: Improve iOS Card Crop Quality

**Planned by:** Codex
**Date:** 2026-04-29

## Approach

Unify crop generation around `CardCropService` so manual crop-enabled capture, photo-library crop-enabled upload, and auto-scan still captures can use the same Vision rectangle refinement and perspective correction. Keep auto-scan live detection unchanged for latency, but pass the captured still and YOLO box into the shared crop service after capture. Preserve crop-disabled mode as a full-image upload path.

## Implementation Steps

1. Add `CardCropHint` to `CardCropService` with an optional top-left-origin YOLO box and a `preferSingleCrop` flag.
2. Update `CardCropService.detectAndCrop` to:
   - normalize image orientation,
   - convert YOLO hints into Vision coordinates,
   - run rectangle detection with ROI plus full-image fallback when a hint exists,
   - rank filtered rectangles,
   - perspective-correct selected quads,
   - normalize output to portrait `63:88`,
   - fall back to a YOLO axis-aligned crop only if Vision refinement produces no crop.
3. Update `RectangleFilter` to:
   - enable containment suppression for crop generation,
   - rank candidates by confidence, aspect closeness, area, and optional YOLO overlap,
   - support single-best crop selection,
   - sort multi-card crop results by top-left reading order using Vision bottom-left coordinates.
4. Update `AutoScanViewModel` to call the shared crop service with the still-photo YOLO box after capture. Keep the same YOLO box for detection-zone calibration.
5. Add focused tests for:
   - crop output portrait orientation and card aspect,
   - YOLO fallback crop behavior,
   - hint-biased rectangle ranking,
   - crop-mode containment suppression,
   - corrected top-left reading order,
   - test injection signature changes in `AutoScanViewModel`.

Dependencies: step 4 depends on steps 1 and 2. Step 5 depends on the production API shape from steps 1 through 4.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/CardCropService.swift` | Add crop hints, Vision ROI/full-image detection flow, YOLO fallback, reduced padding, and portrait card-aspect normalization. |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/RectangleFilter.swift` | Add crop candidate ranking, hint scoring, containment suppression in crop mode, and top-left reading order. |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift` | Pass auto-scan still captures through shared crop service with YOLO hint. |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CardCropServiceTests.swift` | Add crop aspect/orientation and YOLO fallback assertions. |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RectangleFilterTests.swift` | Add ranking, containment suppression, and reading-order tests. |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanViewModelTests.swift` | Update crop injection closure for optional crop hints. |

## Risks and Open Questions

- Vision ROI coordinates with `regionOfInterest` are normalized in image coordinates. To avoid losing candidates from a bad hint or ROI behavior, the implementation should combine ROI results with full-image results when a hint exists.
- Output normalization by resizing to `63:88` may slightly distort pixels if `CIPerspectiveCorrection` output is off-aspect. This is acceptable for recognition consistency but should be revisited if visual fidelity becomes a product requirement.
- Geometry-only crop logic cannot reliably detect whether a card is upside down; 180-degree correction remains out of scope.
- Auto-scan still-photo refinement adds work only after capture. It should not affect live-frame detection latency, but capture-to-enqueue timing should be checked on device.
- Local simulator validation may be blocked by the known CoreSimulator/Xcode runtime mismatch.

## Decisions

- Preserve crop-off behavior as full-image upload.
- Use Vision still-photo refinement first for auto-scan.
- Keep YOLO box cropping only as fallback.
- Do not add new ML dependencies or train a model for this iteration.
- Do not touch downstream recognition code or API contracts.

## Verification Plan

Run the targeted XCTest command:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/AutoScanCropHelperTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests
```

If blocked by simulator/runtime issues, run:

```sh
swiftc -parse apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/CardCropService.swift apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/RectangleFilter.swift apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CardCropServiceTests.swift apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RectangleFilterTests.swift apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanViewModelTests.swift
```

Record any blocked validation explicitly in `review.md`.
