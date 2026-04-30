# Debug Raw Capture Saving

## Purpose

The crop pipeline still needs original camera source images to build reliable crop fixtures. Some existing labeled fixtures are final crop outputs, which can prove that an evaluator distinguishes good and bad crops, but cannot replay the source capture through the crop pipeline.

The debug raw-capture save option captures the original camera JPEG bytes before any crop, normalization, or recognition work. These saved Photos assets can be exported later and paired with ground-truth card quads.

## User-Facing Debug Behavior

- Debug builds expose Settings > Diagnostics > `Save Raw Captures to Photos`.
- The toggle defaults to off and persists in `UserDefaults`.
- When enabled, raw camera captures from manual scan and auto-scan are saved to Photos.
- Imported photo-library images are not saved again.
- Permission denial or save failure logs a debug message and does not block recognition.

## Implementation Decisions

- The setting and UI are guarded with `#if DEBUG`.
- The saver is also debug-only and compiled out of release builds.
- The saver writes `RecognitionImagePayload.uploadData`, not `displayImage.jpegData(...)`, to preserve the original camera capture bytes.
- Photos permission uses `PHPhotoLibrary.requestAuthorization(for: .addOnly)` because the app only needs to add diagnostic assets.
- Tests inject a spy `RawCaptureSaving` implementation and never write to `PHPhotoLibrary`.
- Manual capture saves after `captureCoordinator.capturePhoto()` returns and before `enqueueForRecognition`.
- Auto-scan saves after still capture and before `cropCapturedPayload`.

## Files

- `apps/ios/MTGScanner/Support/Info.plist`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/AppModel.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Settings/SettingsView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Support/RawCaptureDebugSaver.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AppModelCropToggleTests.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanViewModelTests.swift`

## Verification

Targeted raw-capture tests passed on iOS 18.6 `iPhone 16` simulator:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesDefaultIsFalse -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesPersistsToUserDefaults -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesLoadsPersistedValue -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverIsSkippedWhenDebugToggleDisabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverReceivesOriginalUploadDataWhenDebugToggleEnabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testAutoCapturedPayloadSavesOriginalBytesBeforeRecognitionWork -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testGenericEnqueueDoesNotSaveImportedPhotoPayloads
```

Release build passed with signing disabled:

```sh
xcodebuild build -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO
```

## Remaining Manual Check

Run a debug build on a physical iPhone, enable the toggle, grant add-only Photos access, capture manual and auto-scan images, and confirm new Photos assets are the uncropped camera captures.
