# Agent State

## Goal

Improve iOS MTG card crop detection so crop-enabled manual/photo-library scans and auto-scan produce tight, de-skewed card crops. Current scope is the iOS crop pipeline and diagnostics: `CardCropService`, `RectangleFilter`, auto-scan crop handoff, XCTest crop evaluation, production crop-quality validation, and debug-only raw camera capture saving. Do not change recognition models, API contracts, server recognition logic, or downstream recognition behavior.

## Current Task

The latest phase added `tmp/table-scan-2` as a permanent crop-quality regression set and extended runtime crop validation to non-hinted table/manual multi-card cropping. Implementation is complete for the current table-scan guardrail, split-card merge behavior, fixture imports, and documentation updates.

Relevant docs:

- `docs/work-efforts/2026-04-29-improve-ios-crop/findings.md`
- `docs/work-efforts/2026-04-29-improve-ios-crop/future-work.md`
- `docs/work-efforts/2026-04-29-improve-ios-crop/raw-capture-debug-saving.md`
- `docs/decisions/adr-0005-auto-scan-crop-validation.md`
- `docs/decisions/adr-0006-table-scan-crop-quality-validation.md`

## Relevant Files

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/CardCropService.swift`
  - Shared still-image crop service using Vision rectangles, `CIPerspectiveCorrection`, YOLO hint fallback, portrait card-aspect normalization, and hinted single-crop validation.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/CardCropService+Quality.swift`
  - Non-hinted multi-card crop-quality filtering and split-card merge helpers for table/manual scans.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/CropQualityEvaluator.swift`
  - Production crop-quality metrics shared with tests: edge brightness/dark border/background checks, printed-layout skew, and size-vs-hint validation.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/RectangleFilter.swift`
  - Candidate filtering/ranking. Hinted single-crop mode rejects candidates that are too small or poorly supported by the YOLO hint.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift`
  - Auto-scan still capture passes the YOLO box as a `CardCropHint` into `CardCropService`; debug builds also inject/use `RawCaptureSaving`.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Support/RawCaptureDebugSaver.swift`
  - Debug-only Photos add-only saver using `RecognitionImagePayload.uploadData`.
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CardCropEvaluationTests.swift`
  - Labeled-output evaluator that reuses production crop-quality metrics.
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CardCropServiceTests.swift`
  - Includes auto-scan regression coverage for `IMG_1955`, `IMG_1956`, `IMG_1957`, and `IMG_1960`, plus table-scan source-image count coverage for `IMG_1968`, `IMG_1969`, `IMG_1973`, `IMG_1979`, `IMG_1980`, and `IMG_1981`.
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RectangleFilterHintTests.swift`
  - Hinted ranking tests for rejecting text-box-sized candidates and accepting lower-confidence full-card candidates.
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RectangleFilterGeometryTests.swift`
  - Geometry constant and helper tests split out to keep lint complexity in bounds.
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CropEvaluationFixtures/`
  - Labeled crop outputs plus auto-scan and `table-scan-2` source-image regression fixtures.

## Decisions

- Preserve crop-disabled behavior as full-image upload.
- Auto-scan still-photo crop generation should use Vision refinement with the YOLO box as a hint; live-frame auto-scan detection remains unchanged.
- Hinted auto-scan Vision crops must be validated before return. If no Vision crop passes validation, return the YOLO axis-aligned crop instead of an interior printed-feature crop.
- Hinted `preferSingleCrop` ranking returns an ordered eligible list instead of truncating to the top candidate before crop validation.
- Hinted ranking rejects candidates much smaller than the hint or poorly supported by the hint.
- The bin/stack setup can create strong, straight rectangles from cards underneath the target. Outer rectangle straightness alone is not enough to diagnose skew.
- Production and tests share `CropQualityEvaluator` to avoid drift between test classification and runtime crop selection.
- Debug raw capture saving is a fixture-generation diagnostic only. It remains default-off, debug-only, and absent from release UI/runtime.
- Raw capture saving preserves `RecognitionImagePayload.uploadData`; do not re-encode `displayImage`.
- Imported photo-library images are intentionally not saved again.
- ADR: `docs/decisions/adr-0005-auto-scan-crop-validation.md`.
- Non-hinted table/manual multi-card crops are validated with `CropQualityEvaluator`.
- Under-crop and over-crop are hard table-scan rejection signals; skew alone is not.
- Existing two-complete-card table behavior is preserved with a narrow fallback when one complete crop trips a lightweight quality flag.
- Likely split-card printed-half detections are merged into one physical-card crop.
- ADR: `docs/decisions/adr-0006-table-scan-crop-quality-validation.md`.

## Constraints

- Scope is limited to crop and capture diagnostics/pipeline.
- Do not modify recognition model, server recognition logic, API contracts, or downstream pipeline.
- Prefer Apple-native frameworks already in use: Vision, CoreImage, UIKit, AVFoundation, Photos.
- Evaluation harness must run in Xcode/XCTest.
- Use the iOS 18.6 `iPhone 16` simulator for targeted tests when available.
- Do not use `swift test` as the primary verifier; this is an iOS-only package and a macOS package build fails on UIKit imports.
- Worktree contains unrelated dirty files; do not revert or edit unrelated changes.

## Commands Run / Results

- Focused auto-scan crop regression baseline before this fix:
  - `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests`
  - Failed only on the known crop-filter expectation `RectangleFilterNMSTests/testCropFilterDoesNotApplyContainmentSuppression()`.
- Focused auto-scan crop regression verification after this fix:
  - `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterHintTests -only-testing:MTGScannerKitTests/RectangleFilterGeometryTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests`
  - Passed.
- `make ios-lint` after this fix:
  - Failed only on pre-existing unrelated violations in `AppModel.swift`, `MotionBurstDetector.swift`, and `AutoScanViewModelTests.swift`.
  - No crop-related changed file currently contributes a SwiftLint violation.
- `git diff --check`
  - Passed.
- Table-scan-2 crop regression verification after helper refactor:
  - `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterHintTests -only-testing:MTGScannerKitTests/RectangleFilterGeometryTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests`
  - Passed.
- Prior raw-capture diagnostic validation:
  - Targeted raw-capture tests passed.
  - Release build guard passed.
- `swift test` from `apps/ios/MTGScannerKit`:
  - Failed with `no such module 'UIKit'`, because SwiftPM attempted a macOS build. Use Xcode iOS test commands instead.

## Known Issues

- Current auto-scan regression fixtures include source images and bad outputs, but the source tests still use approximate YOLO hints rather than annotated ground-truth card quads.
- Table-scan `IMG_1968-crop3` and `IMG_1979-crop2` still pass crop-only quality metrics even though they are semantically undesirable outputs. This is documented as an evaluator limitation, not treated as solved.
- Full end-to-end crop evaluation still needs original source images plus expected card quads for precise geometry assertions.
- `make ios-lint` currently fails on pre-existing unrelated files:
  - `AppModel.swift`: file length and type body length.
  - `MotionBurstDetector.swift`: redundant setter access control.
  - `AutoScanViewModelTests.swift`: force unwrap, line length, and type body length.
- Physical-device Photos saving has not yet been manually verified. Unit tests cover gating and byte preservation via spy saver, not actual `PHPhotoLibrary` writes.
- Unrelated dirty files existed before/alongside this crop work:
  - `apps/ios/MTGScanner.xcodeproj/xcshareddata/xcschemes/MTGScanner.xcscheme`
  - `services/api/data/pricing/model_prices.json`

## Next Steps

1. Add annotated ground-truth quads for source fixtures and compare generated crop geometry against those quads.
2. Use a debug build on a physical iPhone to capture more raw source images for under-crop, over-crop, skewed bin/stack, and good cases.
3. Confirm raw Photos saving works with add-only permission on a physical device.
4. Resolve unrelated SwiftLint violations if lint must be green before commit.
5. Run focused crop regression and raw-capture test sets after each crop pipeline change.

## Latest Table-Scan-2 Update

- Added `tmp/table-scan-2` as permanent crop regression fixtures:
  - `IMG_1968`: expects 4 complete card crops.
  - `IMG_1969`: expects 4 complete card crops while rejecting loose/aggressive candidates.
  - `IMG_1973`: expects 1 whole split-card crop, not two printed-half crops.
  - `IMG_1979`: expects 1 complete-card crop and rejects the partial visible card.
  - `IMG_1980`: expects 1 tight crop with the bottom preserved.
  - `IMG_1981`: expects 1 crop; the sample note's `IMG_1980.jpg` reference is treated as an `IMG_1981` typo.
- Added `CardCropService+Quality.swift` for non-hinted multi-card quality filtering and split-card merge helpers.
- Multi-card runtime filtering now hard-rejects under/over crops, treats skew alone as a soft signal, and preserves existing two-complete-card table behavior.
- Verification passed:
  - `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterHintTests -only-testing:MTGScannerKitTests/RectangleFilterGeometryTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests`
  - `git diff --check`
- `make ios-lint` still fails only on unrelated baseline violations in `AppModel.swift`, `MotionBurstDetector.swift`, and `AutoScanViewModelTests.swift`.
- Known limitation: crop-only quality metrics still cannot reject every semantic partial/missing-title crop without false positives; `IMG_1968-crop3` and `IMG_1979-crop2` are documented as remaining evaluator limitations.
