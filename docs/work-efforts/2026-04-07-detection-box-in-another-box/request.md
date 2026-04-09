# Request: Suppress nested detection boxes in scan mode

**Date:** 2026-04-07
**Author:** User

## Goal

Fix the scan-mode bug where a detection box appears inside another detection box. These inner boxes are almost certainly false positives because there are not cards inside cards, and in practice they seem to be internal card features rather than real card candidates.

## Requirements

1. Scan mode should not surface a smaller card-shaped detection inside a larger detected card.
2. The solution should account for the fact that the smaller boxes are often card features, not duplicate card detections.
3. If advisable, reuse the existing YOLO card detector from auto-scan to help distinguish real cards from internal card features.
4. Preserve scan-mode overlays and tracking behavior for valid cards.

## Scope

**In scope:**
- `VNDetectRectanglesRequest` filtering in scan mode.
- Reuse of the existing on-device YOLO card detector as scan-mode validation.
- Unit coverage for the new suppression and validation behavior.

**Out of scope:**
- Auto-scan state-machine changes.
- Backend or recognition changes.
- Model retraining.
- Broad scan UX redesign.

## Verification

- `xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`
- `xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:MTGScannerKitTests/RectangleFilterTests -only-testing:MTGScannerKitTests/ScanYOLOSupportTests -only-testing:MTGScannerKitTests/YOLOCardDetectorTests`
- `git diff --check`
- Manual follow-up recommended on device or simulator camera preview to tune thresholds if needed.

## Context

Files or docs the agent should read before starting:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/CardDetectionEngine.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/RectangleFilter.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/YOLOCardDetector.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RectangleFilterTests.swift`
- `apps/ios/CLAUDE.md`

## Notes

The user clarified that the smaller nested boxes are usually not duplicates; they are likely picking up features inside a card. That made semantic validation with YOLO appropriate as a second-stage check rather than replacing the scan-mode rectangle path entirely.
