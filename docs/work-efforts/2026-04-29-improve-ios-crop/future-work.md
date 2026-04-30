# Future Work: iOS Crop Follow-Up

## Goal

Turn the current crop diagnostics and labeled-output evaluator into a source-image regression suite, then finish the crop candidate fixes without relying on manually inspecting bad crop outputs.

## Current State

- Shared still-image crop refinement exists in `CardCropService`.
- Auto-scan still captures pass through shared crop generation with YOLO hints.
- Labeled crop-output fixtures exist and can classify known output failure classes.
- Debug builds can now save original camera JPEG bytes to Photos before crop or recognition.
- Targeted raw-capture tests pass.
- Release build compiles with debug-only raw-capture code compiled out.

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

3. Extend the crop evaluation harness.
   - Run source images through `CardCropService.detectAndCrop`.
   - Compare output geometry against expected quads or expected crop properties.
   - Keep the existing labeled-output evaluator as a diagnostic classifier, but make source fixtures the primary regression guard.

4. Resolve the current crop-filter test failure.
   - Failing test observed during full suite:
     `RectangleFilterNMSTests/testCropFilterDoesNotApplyContainmentSuppression()`
   - Failure text:
     `XCTAssertEqual failed: ("1") is not equal to ("2")`
   - This is in the rectangle-filter work area, not the raw-capture diagnostic path.
   - Reconcile the intended behavior between crop-mode containment suppression and NMS tests before changing production ranking again.

5. Add production crop candidate validation.
   - Reuse the printed-layout straightness idea from the evaluator after `CIPerspectiveCorrection`.
   - Reject candidates with straight outer edges but tilted internal printed layout.
   - Retry alternate Vision candidates before falling back to YOLO axis-aligned crop.

6. Run device checks.
   - Confirm raw Photos saving works with add-only permission on physical device.
   - Measure auto-scan capture-to-enqueue latency after Vision refinement.
   - Compare recognition output quality before and after source-fixture-driven crop changes.

## Suggested Validation Commands

Focused crop regression set:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/AutoScanCropHelperTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests
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
- Avoid reverting unrelated dirty worktree files. Several crop-evaluation and rectangle-filter files may already be modified when this work resumes.
