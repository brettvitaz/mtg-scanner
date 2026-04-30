# Review: Improve iOS Card Crop Quality

**Reviewed by:** Codex
**Date:** 2026-04-29

## Summary

**What was requested:** Improve iOS MTG card crop quality across crop-enabled manual/photo-library flows and auto-scan, while preserving crop-disabled full-image upload and avoiding recognition pipeline changes.

**What was delivered:** Shared Vision-based still-image crop refinement with YOLO hints, perspective correction, tighter padding, portrait card-aspect output normalization, auto-scan integration, focused tests, and a debug-only raw camera capture saver for source fixture creation.

**Deferred items:** Source-image fixture capture, ground-truth quad annotation, on-device latency/recognition A/B measurement, and 180-degree card-top orientation correction remain deferred. One full-suite crop-filter test failure is recorded for follow-up in `future-work.md`.

## Code Review Checklist

Evaluate each criterion against the changes made. State pass or fail with brief evidence.

### 1. Correctness

**Result:** pass

The implementation preserves crop-disabled full-image upload by only changing crop-enabled and auto-scan crop paths. Auto-scan still detects cards the same way on live frames, then uses `CardCropService` after still capture with YOLO fallback. Rectangle ranking now supports hinted single-crop selection and top-left multi-card order.

### 2. Simplicity

**Result:** pass

The change reuses the existing Vision/CoreImage crop service instead of adding a new pipeline or dependency. The main added concepts are `CardCropHint` and `RectangleFilter.rank`, both directly tied to the planned behavior.

### 3. No Scope Creep

**Result:** pass

Changes are limited to crop generation, crop candidate filtering, auto-scan crop handoff, debug-only diagnostic saving, and tests. There are no server, recognition model, or API contract changes. The only UI addition is a debug-only Settings diagnostics toggle.

### 4. Tests

**Result:** pass

Tests were added for output aspect/orientation, YOLO fallback, hint-biased ranking, crop-mode containment suppression, reading order, updated auto-scan crop injection, debug raw-capture persistence, saver gating, and original-byte preservation. The focused crop and raw-capture test sets run through the `MTGScannerKitTests` scheme on the iOS 18.6 `iPhone 16` simulator.

### 5. Safety

**Result:** pass

No destructive filesystem operations were introduced. Auto-scan live-frame processing remains unchanged, and added crop/debug work happens after still-photo capture. Fallback behavior prevents failed Vision refinement from dropping auto-scan crops when YOLO has a usable box. Raw capture saving requests Photos add-only permission, logs denial/failure in debug builds, and does not block recognition.

### 6. API Contract

**Result:** pass

Recognition upload behavior and API schemas are unchanged. Crop-disabled mode still uploads the original full image. Crop-enabled jobs continue to enqueue generated JPEG crop payloads. The debug saver preserves camera `RecognitionImagePayload.uploadData` only for a local Photos diagnostic asset.

### 7. Artifacts and Observability

**Result:** pass

Debug builds can now produce raw camera Photos artifacts for crop fixture creation. Existing crop previews continue to receive the selected crop image in auto-scan.

### 8. Static Analysis

**Result:** pass

`swiftc -parse` passed on the original changed crop source and test files. The focused Xcode test command also passed after the simulator runtime was repaired and the command was updated to use the package test scheme and explicit simulator OS. `swift test` is not a valid verifier for this iOS-only package because it attempts a macOS build and fails on UIKit imports.

## Verification Results

Initial attempted targeted XCTest:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MTGScannerTests/CardCropServiceTests -only-testing:MTGScannerTests/AutoScanCropHelperTests -only-testing:MTGScannerTests/RectangleFilterTests -only-testing:MTGScannerTests/AutoScanViewModelTests
```

Result: blocked before compilation. Xcode reported CoreSimulator `1051.49.0` is older than required `1051.50.0`, the `iPhone 16` simulator could not be found, and the iOS platform/runtime is not installed.

Corrected targeted XCTest:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/AutoScanCropHelperTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests
```

Result: passed. The original command used the app scheme plus `MTGScannerTests/...` filters, which matched zero tests. It also omitted `OS=18.6`, causing Xcode to resolve `name=iPhone 16` as `OS:latest`.

Raw-capture targeted XCTest:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesDefaultIsFalse -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesPersistsToUserDefaults -only-testing:MTGScannerKitTests/AppModelCropToggleTests/testDebugSaveRawCapturesLoadsPersistedValue -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverIsSkippedWhenDebugToggleDisabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testRawCaptureSaverReceivesOriginalUploadDataWhenDebugToggleEnabled -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testAutoCapturedPayloadSavesOriginalBytesBeforeRecognitionWork -only-testing:MTGScannerKitTests/AutoScanViewModelTests/testGenericEnqueueDoesNotSaveImportedPhotoPayloads
```

Result: passed.

Release build guard:

```sh
xcodebuild build -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO
```

Result: passed after approval to run outside the sandbox. This verifies the debug-only raw-capture references compile out in Release.

Full package test suite:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'
```

Result: failed with one known crop-filter failure unrelated to the raw-capture diagnostic phase:

```text
RectangleFilterNMSTests/testCropFilterDoesNotApplyContainmentSuppression()
XCTAssertEqual failed: ("1") is not equal to ("2")
```

Successful parse check:

```sh
swiftc -parse apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/CardCropService.swift apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/RectangleFilter.swift apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CardCropServiceTests.swift apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RectangleFilterTests.swift apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanViewModelTests.swift
```

Result: passed.

## Notes

Known unrelated dirty worktree items existed before documentation was filled and were not modified by this documentation update:

- `services/api/data/pricing/model_prices.json`

This documentation effort filled all four work-effort templates: `request.md`, `plan.md`, `log.md`, and `review.md`.

Supplemental docs added for this phase:

- `raw-capture-debug-saving.md`
- `future-work.md`
