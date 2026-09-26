# Log: Improve iOS Card Crop Quality

## Progress

### Step 1: Audited the existing crop pipeline

**Status:** done

Reviewed the iOS scanner code paths for manual scan, crop-enabled upload, crop-disabled upload, and auto-scan. Found that `CardCropService` already used Vision rectangle observations plus `CIPerspectiveCorrection`, while auto-scan used `YOLOCardDetector` bounding boxes with `AutoScanCropHelper` axis-aligned bitmap cropping.

Deviations from plan: none

---

### Step 13: Added table-scan-2 crop regression coverage

**Status:** done

Imported `tmp/table-scan-2` as permanent XCTest crop fixtures under `CropEvaluationFixtures/table-scan-2` and copied the labeled bad/good crop outputs under `labeled-outputs/table-scan-2`.

Added source-image regression expectations:

- `IMG_1968`: 4 crops.
- `IMG_1969`: 4 crops.
- `IMG_1973`: 1 crop for the whole split card.
- `IMG_1979`: 1 crop for the complete card; partial visible card rejected.
- `IMG_1980`: 1 tight crop with bottom preserved.
- `IMG_1981`: 1 crop, treating the note's `IMG_1980.jpg` reference as an `IMG_1981` typo.

Updated the non-hinted multi-card crop path so it evaluates each Vision crop with `CropQualityEvaluator` before returning crops. Under/over crops are filtered, skew alone is not used as a hard table-scan rejection, and a narrow two-complete-card fallback preserves existing table fixtures when one good card trips a lightweight quality flag. Added split-card merge handling in `CardCropService+Quality.swift` for the `IMG_1973` printed-half case.

Deviations from plan: the runtime validator remains a guardrail, not a ground-truth geometry oracle. The crop-only metrics still cannot reliably reject every semantic partial/missing-title crop without false positives.

---

### Step 14: Ran table-scan regression validation

**Status:** done

Focused crop suite passed:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterHintTests -only-testing:MTGScannerKitTests/RectangleFilterGeometryTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests
```

`git diff --check` passed.

`make ios-lint` failed only on pre-existing unrelated files:

- `AppModel.swift`: file length and type body length.
- `MotionBurstDetector.swift`: redundant setter access control.
- `AutoScanViewModelTests.swift`: force unwrap, line length, and type body length.

No crop-related changed file currently contributes a SwiftLint violation.

Deviations from plan: full lint remains blocked by unrelated baseline violations.

### Step 2: Locked product and implementation decisions

**Status:** done

Recorded two key decisions before implementation: crop-disabled mode remains a full-image upload, and auto-scan should use Vision still-photo refinement with YOLO crop as fallback. Also confirmed the app minimum target is iOS 18, making the existing Vision/CoreImage approach compatible.

Deviations from plan: none

---

### Step 3: Implemented shared crop hints and fallback

**Status:** done

Updated `CardCropService` with `CardCropHint`, YOLO-to-Vision coordinate conversion, ROI plus full-image rectangle detection, reduced crop padding, perspective crop normalization to portrait `63:88`, and YOLO axis-aligned fallback when Vision refinement fails.

Deviations from plan: ROI detection combines ROI and full-image observations rather than using ROI exclusively. This reduces the risk of losing valid rectangles when a YOLO hint is imprecise.

---

### Step 4: Improved rectangle candidate ranking

**Status:** done

Updated `RectangleFilter` to enable containment suppression in crop mode, rank crop candidates by confidence, MTG aspect closeness, area, and optional YOLO overlap, support single-best crop selection, and sort multi-card crops in top-left reading order using Vision bottom-left coordinates.

Deviations from plan: none

---

### Step 5: Wired auto-scan to shared crop generation

**Status:** done

Updated `AutoScanViewModel` so captured still photos are refined through `CardCropService` using the detected YOLO box as a single-crop hint. The YOLO box remains available for detection-zone calibration, and live-frame detection remains unchanged.

Deviations from plan: none

---

### Step 6: Added focused tests

**Status:** done

Updated `CardCropServiceTests`, `RectangleFilterTests`, and `AutoScanViewModelTests` for crop aspect/orientation, YOLO fallback, hint-biased ranking, containment suppression, top-left reading order, and crop injection signature changes.

Deviations from plan: none

---

### Step 7: Ran available validation

**Status:** done

`swiftc -parse` passed for the changed Swift source and test files. Targeted `xcodebuild test` was initially blocked because the local CoreSimulator install was out of date and the requested simulator/runtime was unavailable.

After simulator runtimes were repaired, the targeted XCTest command was corrected to use the `MTGScannerKitTests` scheme, `MTGScannerKitTests/...` filters, and `OS=18.6` for the available `iPhone 16` simulator. The corrected command passed.

Deviations from plan: XCTest execution is blocked by environment setup, not by known code failures.

---

### Step 8: Added debug raw camera capture saving

**Status:** done

Added a debug-only diagnostic setting that saves original camera capture bytes to the iPhone Photos library before crop or recognition work runs. The setting is persisted in `AppModel` as `debugSaveRawCapturesToPhotoLibrary`, defaults to `false`, and is exposed only in debug builds in a Settings > Diagnostics section labeled `Save Raw Captures to Photos`.

Added `NSPhotoLibraryAddUsageDescription` to the app plist and introduced `RawCaptureDebugSaver`, a debug-only Photos add-only writer. The saver requests `.addOnly` authorization, writes `RecognitionImagePayload.uploadData` with `PHAssetCreationRequest.addResource(with: .photo, data:options:)`, logs failures in debug builds, and does not block the capture pipeline on permission denial or save failure.

Manual camera capture now invokes the raw saver after `captureCoordinator.capturePhoto()` returns and before `enqueueForRecognition`. Auto-scan invokes it after still capture and before `cropCapturedPayload`. Photo-library imports intentionally do not call the saver because those images already originated in Photos and saving would create duplicates.

Deviations from plan: none

---

### Step 9: Added debug raw capture tests

**Status:** done

Added guarded tests for the debug-save `AppModel` default, persistence, and load behavior. Added a spy `RawCaptureSaving` implementation in `AutoScanViewModelTests` to verify that saving is skipped when disabled, enabled saving receives the original `RecognitionImagePayload.uploadData`, auto captured payloads save before recognition work, and generic imported-photo enqueue does not save duplicates.

Deviations from plan: actual `PHPhotoLibrary` writes remain out of unit tests by design.

---

### Step 10: Ran raw-capture validation

**Status:** done

Targeted raw-capture tests passed:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesDefaultIsFalse -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesPersistsToUserDefaults -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesLoadsPersistedValue -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverIsSkippedWhenDebugToggleDisabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverReceivesOriginalUploadDataWhenDebugToggleEnabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testAutoCapturedPayloadSavesOriginalBytesBeforeRecognitionWork -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testGenericEnqueueDoesNotSaveImportedPhotoPayloads
```

Release build validation passed after running outside the sandbox:

```sh
xcodebuild build -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO
```

Full `MTGScannerKitTests` execution ran 392 tests and failed one existing crop-filter regression outside the raw-capture diagnostic changes:

```text
RectangleFilterNMSTests/testCropFilterDoesNotApplyContainmentSuppression()
XCTAssertEqual failed: ("1") is not equal to ("2")
```

Deviations from plan: `swift test` is not usable for this iOS-only package on macOS because UIKit is unavailable in a macOS package build. Use Xcode iOS simulator/device commands instead.

---

### Step 11: Fixed auto-scan printed-interior crop regressions

**Status:** done

Added production `CropQualityEvaluator` and moved the lightweight edge/background and printed-layout skew checks out of the test-only evaluator. Updated `CardCropService` so hinted `preferSingleCrop` validates each ranked Vision crop and returns the first acceptable crop. If no hinted Vision candidate passes, the service returns the YOLO axis-aligned crop instead of committing to an interior printed feature.

Updated `RectangleFilter` so hinted single-crop ranking rejects candidates that are too small relative to the YOLO hint or have poor hint/candidate overlap support. Hinted ranking now returns the eligible ordered list for crop validation; no-hint single-crop behavior still truncates to one candidate.

Added regression fixtures for `IMG_1955`, `IMG_1956`, `IMG_1957`, and `IMG_1960`, including the source images and current bad crop outputs. Added focused service/evaluator/filter tests and split rectangle-filter geometry/hint tests so changed files do not add SwiftLint complexity violations.

Deviations from plan: `IMG_1955-crop` is retained in the labeled-output manifest as a passing crop-quality example because the current lightweight evaluator does not classify that output as under-cropped. The source-image regression test still covers `IMG_1955` end to end with an approximate YOLO hint.

---

### Step 12: Ran auto-scan crop regression validation

**Status:** done

Focused crop/view-model suite passed:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterHintTests -only-testing:MTGScannerKitTests/RectangleFilterGeometryTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests
```

`git diff --check` passed.

`make ios-lint` failed only on pre-existing unrelated files:

- `AppModel.swift`: file length and type body length.
- `MotionBurstDetector.swift`: redundant setter access control.
- `AutoScanViewModelTests.swift`: force unwrap, line length, and type body length.

No crop-related changed file contributes a SwiftLint violation after the test/helper split.

Deviations from plan: full lint is not green because of existing unrelated violations outside the crop-regression patch.

---
