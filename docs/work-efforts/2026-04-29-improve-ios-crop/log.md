# Log: Improve iOS Card Crop Quality

## Progress

### Step 1: Audited the existing crop pipeline

**Status:** done

Reviewed the iOS scanner code paths for manual scan, crop-enabled upload, crop-disabled upload, and auto-scan. Found that `CardCropService` already used Vision rectangle observations plus `CIPerspectiveCorrection`, while auto-scan used `YOLOCardDetector` bounding boxes with `AutoScanCropHelper` axis-aligned bitmap cropping.

Deviations from plan: none

---

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
