# Findings: Auto-Scan Crop Failure Regression

## Summary

Four auto-scan regression pairs showed the same failure mode: Vision rectangle detection can select printed card internals instead of the physical card boundary. The previous `preferSingleCrop` path ranked candidates once, cropped the top candidate, and returned it without validating whether the crop still represented the whole card.

## Failure Classes

- `IMG_1955`: under-crop. The bad output captures most of the card face but clips lower card/frame geometry.
- `IMG_1956`: severe under-crop. The bad output is only a `Bloom Tender` text-box fragment.
- `IMG_1957`: severe under-crop. The bad output is only a `Mycoloth` text-box fragment.
- `IMG_1960`: under-crop/skew. The bad output is a large card-face region that misses outer edge geometry and remains perspective-skewed.

## Root Cause

- Vision still-image rectangle detection finds strong high-contrast rectangles inside printed card layouts.
- Hinted ranking did not require enough area or overlap support relative to the YOLO whole-card hint.
- `preferSingleCrop` truncated the ranked list before crop-quality validation, so the service could commit to a high-confidence interior rectangle.
- The existing labeled-output evaluator was test-only, so production crop selection had no quality gate before returning a crop.

## Decisions From This Investigation

- The YOLO hint is treated as the best available whole-card location for auto-scan.
- Vision may refine the YOLO hint, but only if the resulting candidate passes crop-quality validation.
- A YOLO axis-aligned crop is preferable to a perspective-corrected crop of a printed interior feature.
- Hinted single-crop ranking should return an ordered eligible list so `CardCropService` can validate candidates one by one.
- Crop-mode containment suppression should suppress aggregate/container rectangles, but hinted ranking must also reject tiny contained printed features.
- Production and tests should share the same lightweight crop-quality metrics to avoid drift.

## Implemented Fix

- Added `CropQualityEvaluator` in production code and reused it from XCTest.
- Updated `CardCropService` so hinted `preferSingleCrop` validates each ranked Vision crop and returns the first acceptable crop.
- Added fallback to the YOLO axis-aligned crop when no hinted Vision candidate passes validation.
- Updated `RectangleFilter` hinted single-crop ranking to reject candidates that are too small or poorly supported by the hint.
- Added source fixtures and current bad crop outputs for `IMG_1955`, `IMG_1956`, `IMG_1957`, and `IMG_1960`.
- Added auto-scan regression tests that use approximate whole-card YOLO hints and assert that the selected crop is not an interior fragment.

## Verification

Focused crop/view-model suite passed:

```sh
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/CardCropServiceTests -only-testing:MTGScannerKitTests/CardCropEvaluationTests -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/RectangleFilterHintTests -only-testing:MTGScannerKitTests/RectangleFilterGeometryTests -only-testing:MTGScannerKitTests/RectangleFilterNMSTests -only-testing:MTGScannerKitTests/AutoScanViewModelTests
```

`make ios-lint` still fails, but only on pre-existing unrelated violations:

- `AppModel.swift`: file length and type body length.
- `MotionBurstDetector.swift`: redundant setter access control.
- `AutoScanViewModelTests.swift`: force unwrap, line length, and type body length.

No crop-related changed file currently contributes a SwiftLint violation.

## Remaining Risk

- The YOLO fallback is axis-aligned and may include background or perspective skew, but it preserves the full card better than an interior crop.
- The regression hints are approximate whole-card boxes, not ground-truth quads.
- Production validation uses lightweight image metrics. It is a guardrail, not a replacement for source-image fixture evaluation with annotated card geometry.

## Table-Scan-2 Regression Phase

The `tmp/table-scan-2` set adds table/manual multi-card coverage beyond hinted auto-scan:

- `IMG_1968`: four complete card crops.
- `IMG_1969`: four complete card crops while rejecting loose/aggressive candidates.
- `IMG_1973`: one crop for a whole split card instead of the two printed halves.
- `IMG_1979`: one complete-card crop while rejecting the partial visible card.
- `IMG_1980`: one tight crop with the bottom preserved.
- `IMG_1981`: one crop despite the prior no-crop failure; the note's `IMG_1980.jpg` reference is treated as an `IMG_1981` typo.

### Table-Scan Findings

- Non-hinted multi-card scans had no runtime crop-quality gate, so validation existed only in hinted auto-scan.
- `IMG_1973` showed that split-card printed halves can look like two valid rectangles even though the physical card should produce one crop.
- `IMG_1979` showed that partial visible cards need runtime filtering in table-scan mode, not only output classification tests.
- Skew is a weak rejection signal for table layouts: a complete angled table crop can still be usable, so skew alone should not drop a multi-card candidate.
- Crop-only metrics can catch many under/over crops but cannot reliably infer missing title bands or semantic partial-card content without false positives.

### Table-Scan Decisions

- Apply `CropQualityEvaluator` in the non-hinted multi-card path.
- Hard-filter under-crop and over-crop results; do not hard-filter table crops for skew alone.
- Keep a narrow two-complete-card fallback so existing table fixtures are not reduced to one crop by a false positive quality flag.
- Merge likely split-card printed-half detections into one physical-card crop.
- Treat the `IMG_1981` note's `IMG_1980.jpg` reference as a typo.
- Record the decision in `docs/decisions/adr-0006-table-scan-crop-quality-validation.md`.

The implemented fix applies crop-quality filtering to the non-hinted multi-card path. It hard-filters under/over crops, treats skew as a soft table-scan signal, keeps existing two-complete-card table behavior, and adds a split-card merge path for printed-half detections.

Remaining table-scan risk: crop-only metrics cannot reliably classify every semantic partial crop. In particular, the current labeled output test documents that `IMG_1968-crop3` and `IMG_1979-crop2` still pass the lightweight quality evaluator even though they are semantically undesirable. Ground-truth source-image quads are still needed for precise geometry assertions.
