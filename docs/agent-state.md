# Agent State

## Goal

Improve iOS MTG card crop detection so crop-enabled manual/photo-library scans and auto-scan produce tight, de-skewed card crops. Current work is scoped to crop/capture diagnostics and the iOS crop pipeline: `CardCropService`, `RectangleFilter`, auto-scan crop handoff, XCTest evaluation, and debug-only raw camera capture saving for future fixtures. Do not change recognition models, API contracts, server recognition logic, or downstream recognition behavior.

## Current Task

The latest phase is documentation and handoff after adding debug-only raw capture saving. Implementation is complete for the diagnostic saver. Remaining work is future crop-fixture and crop-candidate work, documented in:

- `docs/work-efforts/2026-04-29-improve-ios-crop/future-work.md`
- `docs/work-efforts/2026-04-29-improve-ios-crop/raw-capture-debug-saving.md`

## Relevant Files

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/CardCropService.swift`
  - Shared still-image crop service using Vision rectangles, `CIPerspectiveCorrection`, YOLO hint fallback, and portrait card-aspect normalization.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/RectangleFilter.swift`
  - Candidate filtering/ranking. Crop mode resolves nested rectangles differently from live scan mode.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift`
  - Auto-scan still capture passes the YOLO box as a `CardCropHint` into `CardCropService`; debug builds also inject/use `RawCaptureSaving`.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift`
  - Manual camera capture invokes debug raw saving before recognition enqueue when enabled.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/AppModel.swift`
  - Owns persisted debug-only `debugSaveRawCapturesToPhotoLibrary`, default `false`.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Settings/SettingsView.swift`
  - Debug-only Diagnostics section with `Save Raw Captures to Photos`.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Support/RawCaptureDebugSaver.swift`
  - Debug-only Photos add-only saver using `RecognitionImagePayload.uploadData`.
- `apps/ios/MTGScanner/Support/Info.plist`
  - Includes `NSPhotoLibraryAddUsageDescription`.
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CardCropEvaluationTests.swift`
  - XCTest-only labeled-output evaluator.
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CropEvaluationFixtures/`
  - Labeled JPEG outputs copied from `tmp/auto-scan` and `tmp/table-scan`.
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CropEvaluationFixtures/manifests/labeled-output-manifest.json`
  - Manifest mapping fixture ids to expected failure classes.
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AppModelCropToggleTests.swift`
  - Crop setting tests plus debug raw-capture setting persistence tests.
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanViewModelTests.swift`
  - Auto-scan tests plus spy-saver tests for debug raw capture gating and original bytes.
- `docs/work-efforts/2026-04-29-improve-ios-crop/`
  - Updated request, plan, log, review, raw-capture supplemental doc, and future-work plan.

## Decisions

- Preserve crop-disabled behavior: full image upload.
- Auto-scan still-photo crop generation should use Vision refinement with the YOLO box as a hint; YOLO axis-aligned crop remains fallback only.
- The bin/stack setup can create strong, straight rectangles from cards underneath the target. Outer rectangle straightness alone is not enough to diagnose skew.
- Phase 1 skew detection uses internal printed-layout line straightness, ignoring the outer 10% border area, because recognition cares about printed card layout alignment.
- Live scan filtering can continue preferring an enclosing single-card rectangle. Crop generation should prefer a contained single-card candidate when a larger rectangle appears to be a bin/table/stack container.
- YOLO hint support must be size-sensitive: a large rectangle that merely contains the hint should not score as a perfect match.
- Debug raw capture saving is a fixture-generation diagnostic only. It must be default-off, debug-only, and absent from release UI/runtime.
- Raw capture saving preserves `RecognitionImagePayload.uploadData`; do not re-encode `displayImage`.
- Imported photo-library images are intentionally not saved again.
- Photos permission denial or save failure must not block crop or recognition.

## Constraints

- Scope is limited to crop and capture diagnostics/pipeline.
- Do not modify recognition model, server recognition logic, API contracts, or downstream pipeline.
- Prefer Apple-native frameworks already in use: Vision, CoreImage, UIKit, AVFoundation, Photos.
- Evaluation harness must run in Xcode/XCTest.
- Use the iOS 18.6 `iPhone 16` simulator for targeted tests when available.
- Do not use `swift test` as the primary verifier; this is an iOS-only package and a macOS package build fails on UIKit imports.
- Worktree contains unrelated dirty files; do not revert or edit unrelated changes.

## Commands Run / Results

- Confirmed available simulator:
  - `xcrun simctl list devices available`
  - `iPhone 16`, iOS `18.6` available.
- Phase 1 focused evaluator:
  - `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropEvaluationTests`
  - Passed after adding internal printed-layout straightness metric.
- Phase 2 rectangle filter tests:
  - `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/RectangleFilterTests`
  - Passed at the time of the earlier crop-filter phase.
- Focused crop regression set:
  - `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/AutoScanCropHelperTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests`
  - Passed earlier in the crop phase.
- App scheme compile/test smoke:
  - `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
  - Build/test action succeeded, but executed `0` tests because the app scheme did not pick up package tests.
- Full package test suite:
  - `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
  - Ran `392` tests: `391` passed, `1` failed.
  - Failure: `RectangleFilterNMSTests/testCropFilterDoesNotApplyContainmentSuppression()`, `XCTAssertEqual failed: ("1") is not equal to ("2")`.
  - This failure is in the crop-filter work area and is unrelated to debug raw capture saving.
- Targeted raw-capture diagnostic tests:
  - `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesDefaultIsFalse -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesPersistsToUserDefaults -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesLoadsPersistedValue -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverIsSkippedWhenDebugToggleDisabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverReceivesOriginalUploadDataWhenDebugToggleEnabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testAutoCapturedPayloadSavesOriginalBytesBeforeRecognitionWork -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testGenericEnqueueDoesNotSaveImportedPhotoPayloads`
  - Passed.
- Release build guard:
  - `xcodebuild build -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`
  - Passed after approval to run outside the sandbox. Confirms debug raw-capture references compile out for Release.
- `swift test` from `apps/ios/MTGScannerKit`:
  - Failed with `no such module 'UIKit'`, because SwiftPM attempted a macOS build. Use Xcode iOS test commands instead.

## Known Issues

- Current labeled fixtures are final crop outputs, not original source captures with ground-truth quads. They prove the evaluator distinguishes known good/bad outputs, but cannot fully prove end-to-end crop generation improvements.
- Full end-to-end evaluation still needs original capture images plus expected card quads.
- Full `MTGScannerKitTests` currently has one crop-filter failure:
  - `RectangleFilterNMSTests/testCropFilterDoesNotApplyContainmentSuppression()`
- Physical-device Photos saving has not yet been manually verified. Unit tests cover gating and byte preservation via spy saver, not actual `PHPhotoLibrary` writes.
- Unrelated dirty file present before/alongside this work: `services/api/data/pricing/model_prices.json`.
- Other repo changes may exist outside this task, including local instruction/scheme edits; do not assume they are part of crop work unless verified.

## Next Steps

1. Use a debug build on a physical iPhone to capture raw source images for known under-crop, over-crop, skewed bin/stack, and good cases.
2. Export raw Photos assets and add source fixture metadata with expected card quads.
3. Extend `CardCropEvaluationTests` so source images run through `CardCropService.detectAndCrop`.
4. Resolve `RectangleFilterNMSTests/testCropFilterDoesNotApplyContainmentSuppression()` by reconciling crop-mode containment suppression and NMS expectations.
5. Reuse the printed-layout straightness concept in production crop validation after `CIPerspectiveCorrection`.
6. Add retry logic over alternate Vision candidates before falling back to YOLO axis-aligned crop.
7. Run focused crop regression and raw-capture test sets after each crop pipeline change.
