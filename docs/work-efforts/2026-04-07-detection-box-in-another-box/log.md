# Log: Suppress nested detection boxes in scan mode

## Progress

### Step 0: Re-open the work after review rejection

**Status:** done

Reviewed the rejected follow-up and confirmed two root causes. First, the containment suppression rewrite still relied on confidence ordering and explicitly kept the tighter inner box when a lower-confidence enclosing card arrived later. Second, mode/orientation updates published new state immediately but only queued the scan-YOLO reset asynchronously, leaving a real window where the next processed scan frames could consume stale validation boxes.

Also confirmed that the existing unit tests encoded the wrong behavior: one regression asserted that the higher-confidence inner box should beat the enclosing card. That made it too easy to "fix" the bug in a reviewer-rejected direction while still keeping tests green.

Deviations from plan: this reopened the original work as a correctness rework rather than a threshold-tuning pass.

---

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

### Step 7: Record the corrected algorithm and invariants

**Status:** done

Documented the actual decision rule the detection pipeline should follow: use confidence only for IoU duplicate suppression, then decide containment from the full set of NMS survivors. The correct outcome is to keep the enclosing single-card candidate over nested feature boxes, reject aggregate outers that cover multiple direct peers, preserve crop mode, and tie scan-YOLO cache validity to the same serialized state changes that govern frame processing.

The documentation now calls out the main trade-offs explicitly. The corrected containment logic is more complex than the previous greedy pass, and synchronous queue coordination adds some update-path blocking, but those costs are acceptable because they remove the confidence-order and stale-cache failure modes that reviewers repeatedly flagged.

Deviations from plan: added a focused findings/design note so the algorithm and risks are captured in one place instead of being spread across plan and review prose.

---

### Step 8: Confirm final follow-up and remaining work

**Status:** done

After implementation and focused simulator tests, the remaining open work is no longer in the core algorithm. The unresolved part of the original goal is live-scene confidence: the final implementation still relies on containment and YOLO-support heuristics, so it should be exercised against the original one-card and multi-card camera scenarios before this effort is considered fully closed.

Updated the work-effort docs to state that clearly. The final position is: the code fix is sound and meaningfully better than the rejected attempts, but real scan validation and possible threshold tuning are still the necessary next steps to fully accomplish the product goal.

Deviations from plan: none

---
