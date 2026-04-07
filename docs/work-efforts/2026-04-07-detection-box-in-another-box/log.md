# Log: Suppress nested detection boxes in scan mode

## Progress

### Step 1: Trace the scan-mode detection pipeline

**Status:** done

Inspected the iOS scan pipeline and confirmed that scan mode uses `VNDetectRectanglesRequest` filtered by `RectangleFilter`, while auto mode uses `YOLOCardDetector`. Verified that the current rectangle filter only applied aspect-ratio filtering plus IoU-based NMS, which explains why a small inner box could survive when its IoU with the outer box was low.

Deviations from plan: none

---

### Step 2: Lock the containment and validation strategy

**Status:** done

Discussed the likely cause with the user and confirmed that the smaller nested boxes are usually internal card features rather than duplicate cards. Chose a hybrid approach: reject nested inner rectangles in the geometry filter and use YOLO as a semantic validator for remaining scan-mode proposals rather than replacing scan mode with YOLO.

Deviations from plan: none

---

### Step 3: Implement containment suppression in the rectangle filter

**Status:** done

Updated `RectangleFilter` to add containment thresholds, reusable area and containment helpers, and a second suppression pass after IoU NMS that removes a smaller observation when it is substantially enclosed by a larger accepted one. Added a richer `FilterResult` so the engine can inspect containment suppression counts for debug output without changing the external filter API used by existing callers.

Deviations from plan: exposed an internal richer filter result instead of only returning a plain array so debug logging could report nested suppression directly.

---

### Step 4: Implement throttled YOLO validation in scan mode

**Status:** done

Updated `CardDetectionEngine` scan mode to validate filtered rectangle observations against YOLO detections converted into Vision-style coordinates. Added a small cache with a 250 ms TTL and a stride-based refresh interval so YOLO is not recomputed on every scan frame, and preserved rectangle-only fallback when YOLO is unavailable.

Deviations from plan: none

---

### Step 5: Add focused unit coverage

**Status:** done

Extended `RectangleFilterTests` with nested-box suppression, partial-overlap preservation, and containment helper coverage. Added `ScanYOLOSupportTests` to verify top-left to bottom-left coordinate conversion, YOLO-backed acceptance cases, and rejection of small feature boxes inside a larger card box.

Deviations from plan: skipped engine-level cache-specific tests because the extracted pure support helper coverage was enough for this pass and kept the test surface simpler.

---

### Step 6: Verify build and tests

**Status:** done

Ran `xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`, which succeeded. The first focused test attempt against the app scheme failed because `MTGScannerKitTests` is not a member of that scheme’s test plan, so the verification path was adjusted to use the `MTGScannerKitTests` scheme directly. Ran `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/ScanYOLOSupportTests -only-testing:MTGScannerKitTests/YOLOCardDetectorTests`, which passed. Ran `git diff --check`, which also passed.

Deviations from plan: verification used the dedicated `MTGScannerKitTests` scheme instead of the app scheme because the app scheme is not wired to run those package tests directly.

---
