# Card Detection Feature — Technical Specification

## Purpose

This document is a directive for an AI coding agent (Claude Code) implementing a real-time card detection feature in an iOS app. The feature uses the device camera to locate and highlight up to 9 rectangular card-shaped objects in the live preview. It must handle two environments: cards laid out on a flat surface (table) and cards displayed in a card binder (sleeved in a grid, with plastic overlay and partial occlusion).

---

## 1. Feature Requirements

### 1.1 Core Behavior

- Display a full-screen live camera preview using `AVCaptureSession` and `AVCaptureVideoPreviewLayer`.
- Analyze each video frame to detect rectangular objects matching the aspect ratio of a standard trading card (63mm × 88mm, approximately 1:1.397).
- Draw a visible bounding overlay (colored border, semi-transparent fill) on the live preview around each detected card.
- Detect and highlight **up to 9 cards simultaneously** in a single frame.
- Detection should run continuously at a usable frame rate (target: ≥15 FPS detection cycle on iPhone 12 or newer).

### 1.2 Supported Scenarios

| Scenario | Description | Challenges |
|---|---|---|
| **Table** | 1–9 cards laid on a flat, solid-color surface | Varying card orientation, possible overlap, shadows |
| **Binder** | Cards in a 3×3 (or similar) grid binder page behind a plastic sleeve | Reflective glare, uniform grid spacing, partial card edges hidden by sleeve borders, low contrast between adjacent cards |

### 1.3 Non-Goals (for initial implementation)

- Card *identification* (recognizing which specific card it is). This feature only detects card *locations*.
- OCR or text extraction from cards.
- Augmented reality anchoring or 3D pose estimation.
- Persisting detected card positions across frames (no tracking continuity required yet — frame-by-frame detection is acceptable).

---

## 2. Technology Stack

### 2.1 Frameworks

| Framework | Role |
|---|---|
| **AVFoundation** | Camera session, video capture, preview layer |
| **Vision** | `VNDetectRectanglesRequest` for rectangle detection; fallback to `VNCoreMLRequest` if a custom model is introduced later |
| **SwiftUI** | Host view; use `UIViewControllerRepresentable` to bridge the camera UIKit layer |
| **CoreImage** | Optional — perspective correction if needed for binder pages |

### 2.2 Minimum Deployment Target

- iOS 16.0+ (Vision APIs for rectangle detection are stable from iOS 11+, but SwiftUI lifecycle and modern `AVCaptureSession` configuration APIs benefit from iOS 16+).
- Swift 5.9+

---

## 3. Architecture

### 3.1 Component Breakdown

```
CardDetectionView (SwiftUI)
  └─ CameraViewController (UIViewControllerRepresentable)
       ├─ CameraSessionManager
       │    ├─ AVCaptureSession (configured for .hd1280x720 or .hd1920x1080)
       │    ├─ AVCaptureVideoPreviewLayer (displayed to user)
       │    └─ AVCaptureVideoDataOutput (frame buffer → Vision pipeline)
       ├─ CardDetectionEngine
       │    ├─ Primary: VNDetectRectanglesRequest (aspect ratio–constrained)
       │    ├─ Binder mode: Contour-based fallback (VNDetectContoursRequest)
       │    └─ Post-processing: NMS, aspect ratio filtering, grid inference
       └─ OverlayRenderer
            └─ CALayer-based bounding boxes on detectionLayer (sibling of previewLayer)
```

### 3.2 Data Flow

```
Camera Frame (CMSampleBuffer)
  → CVPixelBuffer extracted
  → VNImageRequestHandler created per frame
  → Perform VNDetectRectanglesRequest
  → Filter results by aspect ratio + minimum size
  → (Binder mode) Apply grid regularization heuristic
  → Transform Vision normalized coordinates → preview layer coordinates
  → Draw/update CAShapeLayer overlays on detectionLayer
```

### 3.3 Threading Model

- Camera delegate callback arrives on a dedicated serial `DispatchQueue` (`"com.app.camera-queue"`).
- Vision requests execute on that same queue (blocking is acceptable — AVFoundation will drop frames rather than queue them, which is the correct behavior).
- Overlay drawing dispatches to `DispatchQueue.main` for layer updates.
- **Never hold more than 1 Vision request in flight.** Use a boolean flag (`isProcessingFrame`) to skip frames while detection is running.

---

## 4. Implementation Details

### 4.1 Camera Session Setup

```swift
// Key configuration points:
let session = AVCaptureSession()
session.sessionPreset = .hd1280x720  // Balance between resolution and processing speed.
                                      // Do NOT use .photo or .hd4K — too slow for real-time Vision.

// Use back wide-angle camera
let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

// Video data output — delivers CMSampleBuffer frames
let videoOutput = AVCaptureVideoDataOutput()
videoOutput.alwayDiscardsLateVideoFrames = true  // Critical: don't queue frames
videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)

// Preview layer — displays camera feed to user
let previewLayer = AVCaptureVideoPreviewLayer(session: session)
previewLayer.videoGravity = .resizeAspectFill
```

### 4.2 Rectangle Detection Configuration

This is the heart of the feature. `VNDetectRectanglesRequest` must be carefully tuned:

```swift
let request = VNDetectRectanglesRequest(completionHandler: handleDetectedRectangles)

// CRITICAL PARAMETERS — tune these carefully:

// Maximum number of rectangles to return. Set to 9 (our max card count).
// Setting to 0 means "return all" but is slower; 9 is a reasonable cap.
request.maximumObservations = 9

// Aspect ratio of a standard trading card:
// Card is 63mm wide × 88mm tall → ratio = 63/88 ≈ 0.716
// But card may be landscape in frame → also need ~1.397
// Vision's aspect ratio is always ≤ 1.0 (shorter side / longer side)
// So: 63/88 = 0.716
request.minimumAspectRatio = 0.65   // Allow some tolerance below 0.716
request.maximumAspectRatio = 0.80   // Allow some tolerance above 0.716

// Minimum size relative to image dimensions (0.0–1.0).
// A card on a table might be small in frame; in a binder, each card is ~1/9 of the page.
// Start conservative and adjust:
request.minimumSize = 0.05          // Card must be at least 5% of image dimension

// How much detected quadrilateral corners can deviate from 90°.
// Cards are rigid rectangles, but perspective skew is common.
// In binder: sleeve edges are very regular. On table: more skew expected.
request.quadratureTolerance = 15.0  // degrees; default is 30°, tighter is better for cards

// Minimum confidence (0.0–1.0)
request.minimumConfidence = 0.6
```

**Important:** `VNDetectRectanglesRequest` returns `VNRectangleObservation` objects, each with four corner points (`topLeft`, `topRight`, `bottomLeft`, `bottomRight`) in Vision's normalized coordinate system (origin at bottom-left, values 0.0–1.0). You must transform these to the preview layer's coordinate system for overlay drawing.

### 4.3 Coordinate Transformation

Vision coordinates (origin bottom-left, normalized) must be mapped to UIKit screen coordinates (origin top-left, pixel values). The `AVCaptureVideoPreviewLayer` has a built-in helper:

```swift
// Convert Vision bounding box to preview layer coordinates:
let boundingBox = observation.boundingBox  // CGRect in normalized Vision coordinates
let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: boundingBox)

// For corner points (more precise, accounts for perspective):
let topLeft = previewLayer.layerPointConverted(fromCaptureDevicePoint: observation.topLeft)
// ... repeat for all 4 corners
```

**Use the 4-corner approach, not just the bounding box.** Cards viewed at an angle produce a trapezoid, not an axis-aligned rectangle. Drawing a `UIBezierPath` through the 4 transformed corners gives a much more accurate overlay than a simple `CGRect`.

### 4.4 Overlay Rendering

```swift
// Layer hierarchy:
// view.layer
//   ├─ previewLayer (camera feed)
//   └─ detectionLayer (overlay container, same frame as previewLayer)
//        ├─ cardOverlay0 (CAShapeLayer)
//        ├─ cardOverlay1 (CAShapeLayer)
//        └─ ... up to cardOverlay8

// On each detection cycle:
// 1. Remove all sublayers from detectionLayer (or reuse a pool of layers)
// 2. For each detected rectangle, create a CAShapeLayer:
let overlay = CAShapeLayer()
let path = UIBezierPath()
path.move(to: transformedTopLeft)
path.addLine(to: transformedTopRight)
path.addLine(to: transformedBottomRight)
path.addLine(to: transformedBottomLeft)
path.close()

overlay.path = path.cgPath
overlay.strokeColor = UIColor.systemGreen.cgColor
overlay.fillColor = UIColor.systemGreen.withAlphaComponent(0.15).cgColor
overlay.lineWidth = 2.0
detectionLayer.addSublayer(overlay)
```

**Performance note:** Removing and recreating layers every frame can cause flicker. Consider maintaining a pool of 9 `CAShapeLayer` instances and showing/hiding + updating paths rather than add/remove cycles. Use `CATransaction.begin()` / `CATransaction.setDisableActions(true)` / `CATransaction.commit()` to suppress implicit animations on path changes.

### 4.5 Binder Mode — Additional Complexity

Detecting cards in a binder is harder than on a table because:

1. **Low contrast between adjacent cards.** Cards sit edge-to-edge in a grid with minimal gap. Vision may detect the entire binder page as one large rectangle rather than 9 individual cards.
2. **Plastic sleeve glare.** Reflections from overhead lighting create bright spots that break edge detection.
3. **Uniform grid.** The regularity of the grid is actually exploitable — if you detect the *page*, you can subdivide it.

#### Strategy: Hierarchical Detection

Implement a two-pass approach for binder detection:

**Pass 1 — Detect the binder page.**

```swift
// Configure a separate request for the full binder page:
let pageRequest = VNDetectRectanglesRequest(completionHandler: handlePageDetected)
pageRequest.maximumObservations = 1
pageRequest.minimumAspectRatio = 0.60
pageRequest.maximumAspectRatio = 0.95  // Binder pages are roughly letter/A4 ratio
pageRequest.minimumSize = 0.30         // Page should be large in frame
pageRequest.quadratureTolerance = 10.0
```

**Pass 2 — Subdivide the page into a grid.**

Once the page rectangle is detected with its 4 corner points:

```swift
// 1. Use CIPerspectiveCorrection to dewarp the detected page into a flat rectangle.
// 2. Divide the corrected image into a 3×3 grid (most common binder layout).
// 3. For each cell, run VNDetectRectanglesRequest with maximumObservations = 1
//    to find the card within that cell.
//
// OR (simpler, preferred for v1):
// 1. Detect the page corners.
// 2. Mathematically subdivide the quadrilateral into a 3×3 grid using linear
//    interpolation between the corner points.
// 3. Draw overlay borders at the interpolated grid positions.
// 4. Skip per-cell Vision detection entirely — assume each cell contains a card.
```

The simpler "subdivide the quad" approach works well in practice because binder pages have a very regular grid. Use bilinear interpolation across the 4 page corners to compute the 16 grid intersection points (4×4 points forming 9 cells).

```swift
func interpolateGridPoints(
    topLeft: CGPoint, topRight: CGPoint,
    bottomLeft: CGPoint, bottomRight: CGPoint,
    rows: Int, cols: Int
) -> [[CGPoint]] {
    // Returns a (rows+1) × (cols+1) grid of points
    // Each point is computed via bilinear interpolation:
    // P(u,v) = (1-v)*((1-u)*TL + u*TR) + v*((1-u)*BL + u*BR)
    // where u = col/cols, v = row/rows
    var grid: [[CGPoint]] = []
    for row in 0...rows {
        var rowPoints: [CGPoint] = []
        let v = CGFloat(row) / CGFloat(rows)
        for col in 0...cols {
            let u = CGFloat(col) / CGFloat(cols)
            let x = (1-v) * ((1-u) * topLeft.x + u * topRight.x)
                  + v * ((1-u) * bottomLeft.x + u * bottomRight.x)
            let y = (1-v) * ((1-u) * topLeft.y + u * topRight.y)
                  + v * ((1-u) * bottomLeft.y + u * bottomRight.y)
            rowPoints.append(CGPoint(x: x, y: y))
        }
        grid.append(rowPoints)
    }
    return grid
}
```

#### Binder Mode Toggle

Provide a UI toggle (or auto-detect) to switch between table mode and binder mode:

- **Table mode:** Run `VNDetectRectanglesRequest` with `maximumObservations = 9` directly on each frame.
- **Binder mode:** Run page detection → grid subdivision → per-cell overlays.

For v1, a manual toggle is acceptable. Auto-detection (heuristic: "did we find exactly 1 large rectangle with aspect ratio near letter/A4?") can be added later.

---

## 5. Post-Processing & Filtering

### 5.1 Aspect Ratio Validation

Even with Vision's aspect ratio constraints, false positives occur. Apply a secondary filter:

```swift
func isCardAspectRatio(_ observation: VNRectangleObservation) -> Bool {
    let box = observation.boundingBox
    let ratio = min(box.width, box.height) / max(box.width, box.height)
    // Standard card: 63/88 = 0.716 ± tolerance
    return ratio > 0.60 && ratio < 0.82
}
```

### 5.2 Non-Maximum Suppression (NMS)

Vision may return overlapping detections for the same card. Implement IoU-based NMS:

```swift
func nonMaxSuppression(
    observations: [VNRectangleObservation],
    iouThreshold: Float = 0.4
) -> [VNRectangleObservation] {
    // Sort by confidence descending
    // For each observation, compute IoU with all kept observations
    // Discard if IoU > threshold with any kept observation
    // Return kept list (max 9)
}
```

### 5.3 Temporal Smoothing (Optional Enhancement)

To reduce flicker between frames, maintain a short buffer (3–5 frames) of detection results and only display a bounding box if it appears consistently across multiple frames. This is a nice-to-have for v1.

---

## 6. SwiftUI Integration

### 6.1 View Hierarchy

```swift
struct CardDetectionView: View {
    @StateObject private var viewModel = CardDetectionViewModel()
    
    var body: some View {
        ZStack {
            // Camera preview with overlays (UIKit bridge)
            CameraPreviewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()
            
            // HUD overlay
            VStack {
                Spacer()
                HStack {
                    // Card count indicator
                    Text("\(viewModel.detectedCardCount) cards")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    // Mode toggle
                    Picker("Mode", selection: $viewModel.detectionMode) {
                        Text("Table").tag(DetectionMode.table)
                        Text("Binder").tag(DetectionMode.binder)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding()
            }
        }
    }
}
```

### 6.2 UIKit Bridge

```swift
struct CameraPreviewRepresentable: UIViewControllerRepresentable {
    @ObservedObject var viewModel: CardDetectionViewModel
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.delegate = viewModel
        return vc
    }
    
    func updateUIViewController(_ vc: CameraViewController, context: Context) {
        vc.updateDetectionMode(viewModel.detectionMode)
    }
}
```

---

## 7. File Structure

```
CardDetection/
├── Views/
│   └── CardDetectionView.swift           # SwiftUI host view
├── Camera/
│   ├── CameraViewController.swift        # UIKit controller: session + preview + overlay layers
│   ├── CameraSessionManager.swift        # AVCaptureSession setup and lifecycle
│   └── CameraPreviewRepresentable.swift  # UIViewControllerRepresentable bridge
├── Detection/
│   ├── CardDetectionEngine.swift         # Vision request creation, configuration, dispatch
│   ├── RectangleFilter.swift             # Aspect ratio filtering, NMS, binder grid subdivision
│   └── GridInterpolator.swift            # Bilinear interpolation for binder grid computation
├── Overlay/
│   └── DetectionOverlayRenderer.swift    # CAShapeLayer pool management, coordinate transforms
├── Models/
│   ├── DetectedCard.swift                # Struct: corners, boundingBox, confidence
│   └── DetectionMode.swift               # Enum: .table, .binder
└── ViewModels/
    └── CardDetectionViewModel.swift      # ObservableObject: bridges detection results to SwiftUI
```

---

## 8. Key References

These are real, verified resources to consult during implementation:

| Resource | URL | Relevance |
|---|---|---|
| Apple: Recognizing Objects in Live Capture (sample project) | `https://developer.apple.com/documentation/vision/recognizing-objects-in-live-capture` | **Start here.** Official camera + Vision + overlay sample code. |
| Apple: VNDetectRectanglesRequest docs | `https://developer.apple.com/documentation/vision/vndetectrectanglesrequest` | Parameter reference for rectangle detection. |
| Soma Sharma: Real-Time Rectangle Detection on Live Camera | `https://medium.com/@somasharma95/real-time-paper-rectangle-detection-on-live-camera-with-swift-e586f97fcd94` | Complete SwiftUI + AVFoundation + VNDetectRectanglesRequest walkthrough. |
| Fritz.ai: Scanning Credit Cards with Vision | `https://fritz.ai/how-to-scan-credit-cards-with-computer-vision-on-ios/` | Aspect ratio–constrained rectangle detection with perspective correction. Includes GitHub repo. |
| Dabbling Badger: VNDetectRectanglesRequest Deep Dive | `https://www.dabblingbadger.com/blog/2020/2/10/rectangle-detection` | Detailed exploration of all VNDetectRectanglesRequest parameters with visual examples. Has a companion macOS Xcode project on GitHub. |
| neuralception.com: Object Detection App in Swift | `https://www.neuralception.com/detection-app-tutorial-detector/` | Explains the detectionLayer / previewLayer sibling hierarchy and coordinate transforms for bounding box overlay. |
| Roboflow: iOS App with Visual AI | `https://blog.roboflow.com/ios-rf-detr-nano/` | Full pipeline: train custom model → deploy to iOS with camera preview + overlays. Reference if rectangle detection proves insufficient and a custom CoreML model is needed. |

---

## 9. Testing Plan

### 9.1 Unit Tests

- `RectangleFilter`: Verify aspect ratio filter accepts 0.716 ratio, rejects 0.5 and 0.95.
- `GridInterpolator`: Verify that a perfect rectangle (no perspective) produces an evenly spaced grid. Verify that a trapezoid produces correctly interpolated points.
- NMS: Verify overlapping boxes are suppressed; non-overlapping are preserved.

### 9.2 Manual Testing Scenarios

| # | Scenario | Expected Result |
|---|---|---|
| 1 | Single card, flat on table, good lighting | 1 green overlay, tightly framing the card |
| 2 | 5 cards scattered on table, no overlap | 5 overlays, each on a card |
| 3 | 9 cards in 3×3 grid on table | 9 overlays |
| 4 | Cards partially overlapping on table | Detects visible cards; may miss heavily occluded ones (acceptable) |
| 5 | Binder page, 3×3 grid, head-on | 9 overlays in grid pattern |
| 6 | Binder page at ~30° angle | Page detected; grid perspective-corrected; 9 overlays |
| 7 | Binder page with glare from overhead light | Degrades gracefully; some cells may lose detection |
| 8 | Empty binder slots (some cells have no card) | Only occupied cells highlighted (stretch goal; v1 may highlight all 9) |
| 9 | Non-card rectangles (book, phone) on table | Should NOT be highlighted if aspect ratio doesn't match |

---

## 10. Known Limitations & Future Work

- **Binder empty slot detection.** The grid subdivision approach in v1 assumes all 9 slots are occupied. Detecting empty slots requires analyzing pixel content within each cell (e.g., checking for uniform color vs. card artwork). Defer to v2.
- **Overlapping cards on table.** `VNDetectRectanglesRequest` struggles with heavily overlapping rectangles. A custom CoreML model (YOLO-based) trained on card images would handle this better. See Roboflow reference above.
- **Performance on older devices.** If frame rate drops below 10 FPS, reduce session preset to `.vga640x480` or increase the frame skip interval.
- **Card identification.** Once detection is solid, a second-stage identification pipeline (perceptual hashing or a classification model against the Scryfall image database) can be layered on top of detected card regions.
