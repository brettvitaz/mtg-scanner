# iOS App — apps/ios

SwiftUI app for iPhone-first MTG card scanning with on-device detection and cropping.

## Structure

The iOS code is split into two parts:

- **`MTGScanner/`** — Xcode app shell: `@main` entry point, `Info.plist`, `Assets.xcassets`, `MTGCardDetector.mlpackage`. This is the Xcode target that produces the `.app`.
- **`MTGScannerKit/`** — Swift Package containing all production source and tests. SourceKit-LSP indexes this package for IDE tooling (autocomplete, go-to-definition).
- **`MTGScanner.xcworkspace`** — Workspace that references both. **Always open the workspace, not the xcodeproj.**

## Architecture

```
MTGScannerKit/Sources/MTGScannerKit/
  App/
    MTGScannerApp (entry point — stays in MTGScanner/ app target)
    AppModel.swift                   Root @MainActor ObservableObject — app-wide state
    RootTabView.swift                Tab navigation
  Features/
    CardDetection/                   Live camera card detection with overlays
      Detection/
        CardDetectionEngine.swift    Scan rectangle detection + Auto Scan YOLO dispatch
        CardTracker.swift            EMA smoothing + presence hysteresis
        RectangleFilter.swift        Edge-based aspect ratio validation + NMS
        GridInterpolator.swift       Bilinear interpolation for quadrilateral grids
      Camera/
        CameraSessionManager.swift   AVCaptureSession lifecycle
        CameraViewController.swift   UIKit controller: session + preview + overlays
        CameraCaptureCoordinator.swift Photo capture delegate
        CameraPreviewRepresentable.swift UIViewControllerRepresentable bridge
      Overlay/
        DetectionOverlayRenderer.swift  CAShapeLayer pool, coordinate transforms
      Models/
        DetectedCard.swift           Struct: corners, boundingBox, confidence
        DetectionMode.swift          Enum: .scan, .auto
      ViewModels/
        CardDetectionViewModel.swift ObservableObject bridging detection → SwiftUI
    Scan/                            Camera capture and upload flow
    Results/                         Recognition results list with card thumbnails
    CardDetail/                      Card detail view with metadata, edition picker, purchase links
    Correction/                      Legacy manual correction UI
    Settings/                        App configuration
  Services/
    APIClient.swift                  Network client for backend communication
    CardCropService.swift            On-device perspective-corrected cropping
```

## Detection pipeline

1. `CameraSessionManager` delivers `CMSampleBuffer` frames on a dedicated serial queue.
2. `CardDetectionEngine` processes frames on `visionQueue` (one in flight at a time — drops excess frames).
3. **Table mode**: `VNDetectRectanglesRequest` → `RectangleFilter` (edge-based aspect ratio + NMS).
4. **Binder mode**: `VNDetectRectanglesRequest` for page → `GridInterpolator` for 3×3 subdivision.
5. `CardTracker` smooths results with EMA on positions + presence hysteresis.
6. `DetectionOverlayRenderer` draws `CAShapeLayer` overlays on the preview layer (main thread).

## Critical coordinate transform rules

These were established through debugging. Do not deviate:

- **VNDetectRectanglesRequest**: Pass native landscape `CVPixelBuffer` to `VNImageRequestHandler` with **no orientation hint**. Vision detects rectangles within the specified aspect-ratio range regardless of the card's orientation relative to the sensor, so no hint is needed. An orientation hint would cause Vision to return coordinates in a rotated space that mismatches `layerPointConverted`'s expected native sensor input.
- **Vision → screen**: Use `previewLayer.layerPointConverted(fromCaptureDevicePoint:)` — do NOT attempt manual coordinate math. Apply Y-flip first (Vision origin is bottom-left, capture device origin is top-left). `layerPointConverted` handles `videoRotationAngle` and `resizeAspectFill` for all device orientations automatically.
- **Pipeline**: native landscape buffer → Vision normalized coords (native sensor space) → Y-flip → `layerPointConverted` → screen points. This works for portrait, landscape left/right, and portrait upside-down.
- **Landscape support**: The scan screen now allows portrait and landscape orientations. `CameraViewController.updatePreviewOrientation` sets the correct `videoRotationAngle` for each orientation, and `layerPointConverted` maps overlay coordinates correctly without any additional logic in the detection pipeline.

## Coding rules

- Swift 6.0, minimum iOS 18.0 (supports iOS 18 and iOS 26).
- `final class` for view models and services (prevent unintended subclassing).
- `@MainActor` on all UI-bound classes. Bridge from background with `Task { @MainActor in }`.
- No force unwraps (`!`) in production code. `guard let` / `if let` only.
- `[weak self]` in closures on long-lived objects to prevent retain cycles.
- Camera and Vision work on dedicated serial `DispatchQueue`s, never on main thread.
- `CATransaction.setDisableActions(true)` when updating overlay layer paths to prevent implicit animations.
- Session preset: `.hd1920x1080`. Do not use `.photo` or `.hd4K` — too slow for real-time Vision.
- Classes that use GCD-based concurrency (camera/detection layer) are marked `@unchecked Sendable` — do not remove this without auditing the threading model.

## Testing

Do not use `swift test` for this iOS package. Use `make ios-test` or run `xcodebuild test` directly against the workspace and the appropriate scheme.

```bash
xcodebuild test \
  -workspace apps/ios/MTGScanner.xcworkspace \
  -scheme MTGScanner \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | xcpretty
```

Or via Makefile: `make ios-test`

- Tests in `MTGScannerKit/Tests/MTGScannerKitTests/`.
- `final class <Feature>Tests: XCTestCase` naming.
- Force unwraps acceptable in test code for brevity.
- Use `XCTAssertEqual(_:_:accuracy:)` for CGFloat/Double comparisons.
- Test models (initialization, equality, identifiability) and pure logic (filters, interpolation, decoding).
- If you need to target the Swift package tests directly, run `xcodebuild test` with the `MTGScannerKitTests` scheme rather than `swift test`.

## Build verification

Minimum check that the app compiles:

```bash
xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner \
  -sdk iphonesimulator -configuration Debug build
```

Or: `make ios-build`
