# Future Work: iOS Crop Follow-Up

## Goal

Turn the current crop diagnostics and labeled-output evaluator into a source-image regression suite, then finish the crop candidate fixes without relying on manually inspecting bad crop outputs.

## Current State

- Shared still-image crop refinement exists in `CardCropService`.
- Auto-scan still captures pass through shared crop generation with YOLO hints.
- Hinted auto-scan crops are validated before return; the service falls back to YOLO axis-aligned crop if no Vision candidate passes validation.
- `RectangleFilter` rejects hinted candidates that are too small or poorly supported by the YOLO hint.
- Production and tests share `CropQualityEvaluator`.
- Labeled crop-output fixtures exist and can classify known output failure classes.
- Source fixtures and bad outputs now exist for `IMG_1955`, `IMG_1956`, `IMG_1957`, and `IMG_1960`.
- `table-scan-2` source fixtures now cover `IMG_1968`, `IMG_1969`, `IMG_1973`, `IMG_1979`, `IMG_1980`, and `IMG_1981`.
- Non-hinted table/manual multi-card crops now use crop-quality validation for under/over-crop filtering.
- `IMG_1973` split-card printed-half detections are covered by a merge regression.
- Debug builds can now save original camera JPEG bytes to Photos before crop or recognition.
- Targeted raw-capture tests pass.
- Release build compiles with debug-only raw-capture code compiled out.
- Focused auto-scan crop regression tests pass.
- `make ios-lint` still fails on unrelated pre-existing violations in `AppModel.swift`, `MotionBurstDetector.swift`, and `AutoScanViewModelTests.swift`.

## Unfinished Work

1. Capture raw source fixtures.
   - Use a physical iPhone debug build.
   - Enable Settings > Diagnostics > `Save Raw Captures to Photos`.
   - Capture manual and auto-scan examples for under-crop, over-crop, skewed bin/stack, and known-good cases.
   - Export the saved Photos assets without recompression when possible.

2. Add source fixture metadata.
   - Store raw source images under a new test fixture directory.
   - Add a manifest with expected card quads, expected failure class, capture mode, and notes about scene setup.
   - Prefer normalized image coordinates so fixtures are resilient to image size.

3. Strengthen the source fixture evaluation harness.
   - Current source-image regression tests use approximate YOLO hints and crop-quality assertions.
   - Add expected quads or expected crop geometry to reduce dependence on heuristic quality metrics.
   - Keep the existing labeled-output evaluator as a diagnostic classifier, but make annotated source fixtures the primary regression guard.

4. Tune production crop candidate validation.
   - `CropQualityEvaluator` is intentionally lightweight and should be validated against more real captures.
   - The current skew threshold is stricter in labeled-output tests than in production auto-scan validation, because one real regression case produces a usable crop with slight printed-layout skew.
   - Revisit thresholds after more source fixtures exist.
   - Add geometry-aware checks for semantic partial-card cases that crop-only metrics miss, including `IMG_1968-crop3` and `IMG_1979-crop2`.
   - Prefer annotated source quads over further ad hoc threshold tuning when extending table-scan validation.

5. Run device checks.
   - Confirm raw Photos saving works with add-only permission on physical device.
   - Measure auto-scan capture-to-enqueue latency after Vision refinement.
   - Compare recognition output quality before and after source-fixture-driven crop changes.

6. Resolve unrelated lint debt if a green `make ios-lint` is required.
   - `AppModel.swift`: file length and type body length.
   - `MotionBurstDetector.swift`: redundant setter access control.
   - `AutoScanViewModelTests.swift`: force unwrap, line length, and type body length.

## Suggested Validation Commands

Focused crop regression set:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterHintTests -only-testing:MTGScannerKitTests/RectangleFilterGeometryTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests
```

Raw-capture diagnostic tests:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesDefaultIsFalse -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesPersistsToUserDefaults -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesLoadsPersistedValue -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverIsSkippedWhenDebugToggleDisabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverReceivesOriginalUploadDataWhenDebugToggleEnabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testAutoCapturedPayloadSavesOriginalBytesBeforeRecognitionWork -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testGenericEnqueueDoesNotSaveImportedPhotoPayloads
```

Release guard:

```sh
xcodebuild build -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO
```

## Notes for Future Agents

- Do not use `swift test` as the main verifier for this package; it attempts a macOS package build and fails on UIKit imports.
- Use the `MTGScannerKitTests` scheme for package tests. The `MTGScanner` app scheme can build and launch tests but may execute zero package tests.
- Keep raw-capture saving default-off and debug-only.
- Table-scan crop-quality validation intentionally treats skew as a soft signal; do not change it to a hard rejection without adding source-image regression coverage for angled complete cards.
- `IMG_1981` is the intended source fixture despite the note typo referring to `IMG_1980.jpg`.
- Avoid reverting unrelated dirty worktree files. Current unrelated dirty files include the app scheme and API pricing model file.
