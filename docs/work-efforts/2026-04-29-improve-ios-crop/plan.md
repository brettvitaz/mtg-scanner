# Plan: Improve iOS Card Crop Quality

**Planned by:** Codex
**Date:** 2026-04-29

## Approach

Unify crop generation around `CardCropService` so manual crop-enabled capture, photo-library crop-enabled upload, and auto-scan still captures can use the same Vision rectangle refinement and perspective correction. Keep auto-scan live detection unchanged for latency, but pass the captured still and YOLO box into the shared crop service after capture. Preserve crop-disabled mode as a full-image upload path.

After the first crop-quality pass, add a debug-only raw camera capture save option. This diagnostic path should preserve original camera JPEG bytes before crop or recognition work so failed crop cases can be converted into source-image fixtures with ground-truth quads. The option must default off, compile out of release builds, and never duplicate imported photo-library images.

After the auto-scan regression pass, hinted single-crop selection also validates candidate crop quality before return. Vision refinement is still preferred when it produces a usable crop, but a YOLO axis-aligned crop is preferable to a perspective-corrected interior printed-feature crop.

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

## Supplemental Diagnostic Steps

1. Add a debug-only `AppModel.debugSaveRawCapturesToPhotoLibrary` setting persisted in `UserDefaults`, defaulting to `false`.
2. Add a debug-only Settings > Diagnostics toggle named `Save Raw Captures to Photos` with copy explaining that original camera JPEGs are saved before crop/recognition for crop diagnosis.
3. Add `NSPhotoLibraryAddUsageDescription` for add-only Photos writes.
4. Add a debug-only `RawCaptureDebugSaver` abstraction that requests `.addOnly` Photos permission and writes `RecognitionImagePayload.uploadData` via `PHAssetCreationRequest.addResource(with: .photo, data:options:)`.
5. Wire raw saving only at camera capture entry points:
   - manual capture after `captureCoordinator.capturePhoto()` returns and before `enqueueForRecognition`,
   - auto capture after `captureCoordinator?.capturePhoto()` returns and before `cropCapturedPayload`.
6. Keep photo-library imports out of the raw-save path because they already originated in Photos and saving would create duplicates.
7. Add tests for debug setting persistence and saver gating/original-byte preservation using a spy saver, not real `PHPhotoLibrary` writes.

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

### Supplemental Files

| File | Change |
|------|--------|
| `apps/ios/MTGScanner/Support/Info.plist` | Add `NSPhotoLibraryAddUsageDescription`. |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/AppModel.swift` | Add debug-only persisted raw-capture save flag. |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Settings/SettingsView.swift` | Add debug-only Diagnostics section and toggle. |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift` | Save manual camera raw payload before recognition enqueue when enabled. |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift` | Add debug-only saver injection and save auto camera raw payload before crop. |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Support/RawCaptureDebugSaver.swift` | Add debug-only Photos add-only saver. |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AppModelCropToggleTests.swift` | Add debug-save default/load/persist tests. |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanViewModelTests.swift` | Add spy-saver tests for disabled/enabled/manual-like enqueue/imported-photo/auto paths. |

## Risks and Open Questions

- Vision ROI coordinates with `regionOfInterest` are normalized in image coordinates. To avoid losing candidates from a bad hint or ROI behavior, the implementation should combine ROI results with full-image results when a hint exists.
- Output normalization by resizing to `63:88` may slightly distort pixels if `CIPerspectiveCorrection` output is off-aspect. This is acceptable for recognition consistency but should be revisited if visual fidelity becomes a product requirement.
- Geometry-only crop logic cannot reliably detect whether a card is upside down; 180-degree correction remains out of scope.
- Auto-scan still-photo refinement adds work only after capture. It should not affect live-frame detection latency, but capture-to-enqueue timing should be checked on device.
- Local simulator validation may be blocked by the known CoreSimulator/Xcode runtime mismatch.
- Raw camera capture saving writes user-visible Photos assets in debug builds. It must remain default-off and permission denial must never block recognition.
- Debug raw saving preserves `RecognitionImagePayload.uploadData`; it should not re-encode `displayImage`, because the point is to capture the source bytes before crop and recognition transforms.

## Decisions

- Preserve crop-off behavior as full-image upload.
- Use Vision still-photo refinement first for auto-scan.
- Keep YOLO box cropping only as fallback.
- Validate hinted Vision crops before returning them.
- For hinted auto-scan, rank eligible Vision candidates and try them in order instead of committing to the top candidate before crop validation.
- Reject hinted candidates that are much smaller than the YOLO whole-card hint or poorly supported by it.
- Do not add new ML dependencies or train a model for this iteration.
- Do not touch downstream recognition code or API contracts.
- Debug-only raw capture saving is a diagnostic fixture-generation aid, not product behavior. Release builds must not expose the setting or saver path.
- Imported Photos images are intentionally not saved again.
- Architecture decision recorded in `docs/decisions/adr-0005-auto-scan-crop-validation.md`.
- Table/manual multi-card crop validation is recorded in `docs/decisions/adr-0006-table-scan-crop-quality-validation.md`.
- For table scans, under/over crop signals are hard filters, but skew alone is not.
- Split-card printed-half detections should produce one physical-card crop when geometry indicates a single card.
- Crop-only quality metrics are guardrails; annotated source-image quads remain the preferred long-term regression oracle.

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

For the auto-scan regression crop validation pass, run:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterHintTests -only-testing:MTGScannerKitTests/RectangleFilterGeometryTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests
```

For the raw-capture diagnostic phase, run the targeted tests:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesDefaultIsFalse -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesPersistsToUserDefaults -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesLoadsPersistedValue -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverIsSkippedWhenDebugToggleDisabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverReceivesOriginalUploadDataWhenDebugToggleEnabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testAutoCapturedPayloadSavesOriginalBytesBeforeRecognitionWork -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testGenericEnqueueDoesNotSaveImportedPhotoPayloads
```

For release guard validation:

```sh
xcodebuild build -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO
```
