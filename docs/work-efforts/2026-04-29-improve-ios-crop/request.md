# Request: Improve iOS Card Crop Quality

**Date:** 2026-04-29
**Author:** Brett Vitaz

## Goal

Improve MTG card cropping in the iOS app so recognition receives tighter, de-skewed, consistently oriented card images. The work should cover manual scan captures with crop enabled, photo-library images with crop enabled, and auto-scan captures, while preserving existing scan modes and recognition API behavior.

## Requirements

1. Cropped card images should be tightly bounded with no more than roughly 5% background bleed per edge.
2. Crops should be perspective-corrected so angled cards appear as flat rectangles.
3. Manual crop-enabled capture, photo-library crop-enabled upload, and auto-scan should produce consistent crop quality.
4. Auto-scan should not add live-frame latency; any additional crop refinement should happen after still-photo capture.
5. Crop-disabled mode must preserve the existing behavior of uploading the full image.
6. Do not modify downstream recognition models, API contracts, or server-side recognition logic.
7. Prefer Apple-native frameworks already in use: Vision, CoreImage, UIKit, and AVFoundation.

## Scope

**In scope:**
- Shared still-image crop generation in `CardCropService`.
- Rectangle candidate filtering/ranking in `RectangleFilter`.
- Auto-scan still-photo crop handoff in `AutoScanViewModel`.
- Focused unit tests for crop ranking, fallback behavior, output aspect/orientation, and existing view-model injection points.

**Out of scope:**
- Recognition pipeline or model changes.
- New third-party computer-vision or ML dependencies.
- Training or integrating a new corner/segmentation model.
- UI redesign beyond preserving the existing crop setting behavior.
- 180-degree card-top orientation detection, since crop geometry alone cannot reliably distinguish upside-down card content.

## Verification

Confirm with targeted iOS tests:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/AutoScanCropHelperTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests
```

If simulator execution is unavailable, at minimum run a Swift parse check on the changed Swift files and record the environment blocker.

## Context

Files or docs the agent should read before starting:

- `apps/ios/CLAUDE.md`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/CardCropService.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/RectangleFilter.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanCropHelper.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/YOLOCardDetector.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CardCropServiceTests.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RectangleFilterTests.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanViewModelTests.swift`

## Notes

Decisions recorded before implementation:

- Crop-disabled mode remains full-image upload.
- Auto-scan should use Vision still-photo refinement first, with YOLO axis-aligned crop only as fallback.
- iOS 18 is the minimum deployment target, so Vision/CoreImage APIs used by the existing app are acceptable.
- No recognition API, server, or model changes are allowed for this effort.
