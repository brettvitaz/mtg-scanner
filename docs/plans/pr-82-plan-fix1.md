# Plan: Fix YOLO Overlay Coordinate Mismatch (PR #82 Comment #1)

## Context

The YOLO debug overlay in `DetectionOverlayRenderer` draws bounding boxes at completely wrong screen positions because raw normalized coordinates from the YOLO model are incorrectly scaled by `sourceSize` (the camera capture buffer size) before being fed into Apple's coordinate converter, which expects [0,1] normalized input. This is a P0 correctness bug — the yellow dashed overlay rectangles appear nowhere near actual cards.

## Root Cause

In `updateYOLOOverlay`, lines 64–69:
- `box.rect` is already **normalized** (0–1, top-left origin) per YOLO output docs
- The code multiplies by `sourceSize` (e.g., width=3024), producing pixel values like `(x: 604.8)`
- These are passed to `yoloRectToVision()` which flips Y: `1.0 - maxY` → `-4031.0`
- Then `rectToLayer()` feeds pixel-space values into `layerPointConverted(fromCaptureDevicePoint:)`, which expects normalized [0,1] coordinates

## Fix

### File: `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Overlay/DetectionOverlayRenderer.swift`

**Change 1 — Remove scaling in `updateYOLOOverlay` (lines 62–74):**

Before:
```swift
let path = UIBezierPath()
for box in boxes {
    let rect = CGRect(
        x: box.rect.minX * sourceSize.width,
        y: box.rect.minY * sourceSize.height,
        width: box.rect.width * sourceSize.width,
        height: box.rect.height * sourceSize.height
    )
    let screenRect = rectToLayer(yoloRectToVision(rect), previewLayer: previewLayer)
    path.append(UIBezierPath(rect: screenRect))
}
```

After:
```swift
let path = UIBezierPath()
for box in boxes {
    let screenRect = rectToLayer(yoloRectToVision(box.rect), previewLayer: previewLayer)
    path.append(UIBezierPath(rect: screenRect))
}
```

**Change 2 — Remove `sourceSize` parameter (line 50):**

Before:
```swift
func updateYOLOOverlay(boxes: [CardBoundingBox], sourceSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer) {
```

After:
```swift
func updateYOLOOverlay(boxes: [CardBoundingBox], previewLayer: AVCaptureVideoPreviewLayer) {
```

### Caller Update

**No callers exist currently.** This method appears to be a debug-only API that hasn't been wired into the live detection pipeline yet. No caller updates needed — just fix the signature so it's correct when integrated. The only current references are within `DetectionOverlayRenderer.swift` itself (`setupYOLOOverlay`, `hideYOLOOverlay`).

## Verification

1. Run `make ios-lint` — SwiftLint passes
2. Run `make ios-test` — All tests pass (no test changes expected; this method may not have unit tests)
3. Manual: run fixture camera, enable YOLO debug overlay — yellow dashed boxes should align with actual card edges in the 4 fixture images
