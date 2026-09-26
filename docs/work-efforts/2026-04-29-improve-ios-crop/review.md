# Review: Improve iOS Card Crop Quality

**Reviewed by:** Codex
**Date:** 2026-04-29

## Summary

**What was requested:** Improve iOS MTG card crop quality across crop-enabled manual/photo-library flows and auto-scan, while preserving crop-disabled full-image upload and avoiding recognition pipeline changes.

**What was delivered:** Shared Vision-based still-image crop refinement with YOLO hints, perspective correction, tighter padding, portrait card-aspect output normalization, auto-scan integration, production crop-quality validation, hinted candidate filtering, focused tests, and a debug-only raw camera capture saver for source fixture creation.

**Deferred items:** Ground-truth quad annotation, on-device latency/recognition A/B measurement, physical-device Photos save verification, and 180-degree card-top orientation correction remain deferred.

## Code Review Checklist

Evaluate each criterion against the changes made. State pass or fail with brief evidence.

### 1. Correctness

**Result:** pass

The implementation preserves crop-disabled full-image upload by only changing crop-enabled and auto-scan crop paths. Auto-scan still detects cards the same way on live frames, then uses `CardCropService` after still capture with validated Vision candidates and YOLO fallback. Rectangle ranking now rejects hinted candidates that are too small or poorly supported by the YOLO hint.

### 2. Simplicity

**Result:** pass

The change reuses the existing Vision/CoreImage crop service instead of adding a new pipeline or dependency. The main added concepts are `CardCropHint`, `RectangleFilter.rank`, and `CropQualityEvaluator`, all directly tied to the planned behavior.

### 3. No Scope Creep

**Result:** pass

Changes are limited to crop generation, crop candidate filtering, auto-scan crop handoff, debug-only diagnostic saving, tests, and documentation. There are no server, recognition model, or API contract changes.

### 4. Tests

**Result:** pass

Tests were added for output aspect/orientation, YOLO fallback, auto-scan source regression fixtures, bad crop-output classification, hint-biased ranking, crop-mode containment suppression, reading order, debug raw-capture persistence, saver gating, and original-byte preservation. The focused crop and raw-capture test sets run through the `MTGScannerKitTests` scheme on the iOS 18.6 `iPhone 16` simulator.

### 5. Safety

**Result:** pass

No destructive filesystem operations were introduced. Auto-scan live-frame processing remains unchanged, and added crop/debug work happens after still-photo capture. Fallback behavior prevents failed Vision refinement from returning auto-scan interior crops when YOLO has a usable box. Raw capture saving requests Photos add-only permission, logs denial/failure in debug builds, and does not block recognition.

### 6. API Contract

**Result:** pass

Recognition upload behavior and API schemas are unchanged. Crop-disabled mode still uploads the original full image. Crop-enabled jobs continue to enqueue generated JPEG crop payloads. The debug saver preserves camera `RecognitionImagePayload.uploadData` only for a local Photos diagnostic asset.

### 7. Artifacts and Observability

**Result:** pass

Debug builds can now produce raw camera Photos artifacts for crop fixture creation. Existing crop previews continue to receive the selected crop image in auto-scan.

### 8. Static Analysis

**Result:** pass

The focused Xcode crop/view-model suite passed. `git diff --check` passed. `make ios-lint` fails only on pre-existing unrelated violations in `AppModel.swift`, `MotionBurstDetector.swift`, and `AutoScanViewModelTests.swift`; no crop-related changed file currently contributes a SwiftLint violation. `swift test` is not a valid verifier for this iOS-only package because it attempts a macOS build and fails on UIKit imports.

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

Auto-scan crop regression suite after the validation fix:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterHintTests -only-testing:MTGScannerKitTests/RectangleFilterGeometryTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests
```

Result: passed. The earlier crop-filter expectation was reconciled with intended behavior and renamed to `testCropFilterSuppressesAggregateContainer()`.

SwiftLint:

```sh
make ios-lint
```

Result: failed only on pre-existing unrelated violations:

- `AppModel.swift`: file length and type body length.
- `MotionBurstDetector.swift`: redundant setter access control.
- `AutoScanViewModelTests.swift`: force unwrap, line length, and type body length.

Diff whitespace check:

```sh
git diff --check
```

Result: passed.

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
- `findings.md`
- `docs/decisions/adr-0005-auto-scan-crop-validation.md`

## Table-Scan-2 Review Addendum

Scope reviewed: `CardCropService`, `CardCropService+Quality`, `CropQualityEvaluator`, table-scan fixture tests, and the table-scan-2 fixture imports.

- Complexity: pass. New multi-card quality and split-card logic is split into focused helpers/extensions; changed crop files do not add SwiftLint complexity violations.
- Correctness: pass with documented limitation. The six `table-scan-2` source fixtures assert the requested counts, including `IMG_1973` whole split-card merge and `IMG_1979` partial-card rejection. Crop-only evaluator limitations remain for semantic partial/missing-title outputs.
- Tests: pass. Source-image regression tests exercise `CardCropService.detectAndCrop(image:)`; labeled-output tests exercise the shared `CropQualityEvaluator`.
- Best practices: pass. No force unwraps added to production code, no API/server/schema changes, and no recognition scope creep.
- Static analysis: partial pass. `git diff --check` passed. `make ios-lint` still fails only on unrelated baseline violations in `AppModel.swift`, `MotionBurstDetector.swift`, and `AutoScanViewModelTests.swift`; no crop-related changed file contributes a lint violation.

Verification:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterHintTests -only-testing:MTGScannerKitTests/RectangleFilterGeometryTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests
```

Result: passed.
