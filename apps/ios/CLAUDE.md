# iOS App — apps/ios

SwiftUI app for iPhone-first MTG card scanning with on-device detection and cropping.

## Architecture

```
MTGScanner/
  App/
    MTGScannerApp.swift              @main entry point
    AppModel.swift                   Root @MainActor ObservableObject — app-wide state
    RootTabView.swift                Tab navigation
  Features/
    CardDetection/                   Live camera card detection with overlays
      Detection/
        CardDetectionEngine.swift    VNDetectRectanglesRequest dispatch (table + binder)
        CardTracker.swift            EMA smoothing + presence hysteresis
        RectangleFilter.swift        Edge-based aspect ratio validation + NMS
        GridInterpolator.swift       Bilinear interpolation for binder grid
      Camera/
        CameraSessionManager.swift   AVCaptureSession lifecycle
        CameraViewController.swift   UIKit controller: session + preview + overlays
        CameraCaptureCoordinator.swift Photo capture delegate
        CameraPreviewRepresentable.swift UIViewControllerRepresentable bridge
      Overlay/
        DetectionOverlayRenderer.swift  CAShapeLayer pool, coordinate transforms
      Models/
        DetectedCard.swift           Struct: corners, boundingBox, confidence
        DetectionMode.swift          Enum: .table, .binder
      ViewModels/
        CardDetectionViewModel.swift ObservableObject bridging detection → SwiftUI
      Views/
        CardDetectionView.swift      SwiftUI host view
    Scan/                            Camera capture and upload flow
      Services/
        CardCropService.swift        On-device perspective-corrected cropping
      ScanView.swift, ScanViewModel.swift
    Results/                         Recognition results list with card thumbnails
    CardDetail/                      Card detail view with metadata, edition picker, purchase links
      CardDetailView.swift           Scrollable detail: image, identity, oracle text, stats, actions
      CardDetailViewModel.swift      State management, printings loading, edition selection
      FullscreenImageView.swift      Tap-to-dismiss fullscreen card/crop image overlay
    Correction/                      Legacy manual correction UI (ConfidenceBadge still used)
    Settings/                        App configuration
  Services/
    APIClient.swift                  Network client for backend communication
```

## Detection pipeline

1. `CameraSessionManager` delivers `CMSampleBuffer` frames on a dedicated serial queue.
2. `CardDetectionEngine` processes frames on `visionQueue` (one in flight at a time — drops excess frames).
3. **Table mode**: `VNDetectRectanglesRequest` → `RectangleFilter` (edge-based aspect ratio + NMS).
4. **Binder mode**: `VNDetectRectanglesRequest` for page → `GridInterpolator` for 3×3 subdivision.
5. `CardTracker` smooths results with EMA on positions + presence hysteresis.
6. `DetectionOverlayRenderer` draws `CAShapeLayer` overlays on the preview layer (main thread).

## Critical coordinate transform rules

These were established through debugging. The pipeline passes an orientation hint to Vision so detection works correctly in all device orientations (portrait and landscape).

- **VNDetectRectanglesRequest**: Pass the current `CGImagePropertyOrientation` (derived from `interfaceOrientation`) to `VNImageRequestHandler`. This tells Vision how to interpret the native landscape pixel buffer so it detects cards that are upright relative to the user.
- **Orientation → `CGImagePropertyOrientation` mapping** (in `CardDetectionEngine.cgOrientation(for:)`):
  - `.landscapeRight` → `.up` (buffer is already upright)
  - `.landscapeLeft` → `.down` (buffer is 180° rotated)
  - `.portrait` → `.right` (buffer needs 90° CW rotation)
  - `.portraitUpsideDown` → `.left` (buffer needs 90° CCW rotation)
- **Vision → screen**: After Vision returns coordinates in the *oriented* image space, un-rotate them to native sensor (capture device) space, then call `previewLayer.layerPointConverted(fromCaptureDevicePoint:)`. Do NOT attempt manual coordinate math beyond this un-rotation.
- **Un-rotation formulas** (Vision oriented `(vx, vy)` → capture device point, in `DetectionOverlayRenderer.visionPointToLayer`):
  - `.landscapeRight`: `(vx, 1-vy)` — Y-flip only
  - `.landscapeLeft`: `(1-vx, vy)` — X-flip only
  - `.portrait`: `(1-vy, 1-vx)` — swap axes, flip both
  - `.portraitUpsideDown`: `(vy, vx)` — swap axes only
- **Pipeline**: native landscape buffer + orientation hint → Vision oriented coords → un-rotate to sensor space → `layerPointConverted` → screen points.
- **Orientation is threaded** from `CameraViewController.viewDidLayoutSubviews` → `CardDetectionEngine.interfaceOrientation` (for Vision) and inline in `engine.onDetection` closure (for renderer).

## Coding rules

- `final class` for view models and services (prevent unintended subclassing).
- `@MainActor` on all UI-bound classes. Bridge from background with `Task { @MainActor in }`.
- No force unwraps (`!`) in production code. `guard let` / `if let` only.
- `[weak self]` in closures on long-lived objects to prevent retain cycles.
- Camera and Vision work on dedicated serial `DispatchQueue`s, never on main thread.
- `CATransaction.setDisableActions(true)` when updating overlay layer paths to prevent implicit animations.
- Session preset: `.hd1920x1080`. Do not use `.photo` or `.hd4K` — too slow for real-time Vision.

## Testing

```bash
xcodebuild test \
  -project apps/ios/MTGScanner.xcodeproj \
  -scheme MTGScanner \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | xcpretty
```

- Tests in `MTGScannerTests/`.
- `final class <Feature>Tests: XCTestCase` naming.
- Force unwraps acceptable in test code for brevity.
- Use `XCTAssertEqual(_:_:accuracy:)` for CGFloat/Double comparisons.
- Test models (initialization, equality, identifiability) and pure logic (filters, interpolation, decoding).

## Build verification

Minimum check that the app compiles:

```bash
xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner \
  -sdk iphonesimulator -configuration Debug build
```
