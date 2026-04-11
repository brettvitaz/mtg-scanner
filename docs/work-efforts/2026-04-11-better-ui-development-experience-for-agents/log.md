# Log: Better UI Development Experience for Agents

## Progress

### Step 1: Filled work-effort templates

**Status:** done

Read all critical source files (`MTGScannerApp.swift`, `CameraViewController.swift`, `CameraSessionManager.swift`, `CameraPreviewRepresentable.swift`, `CardDetectionViewModel.swift`, `ScanView.swift`). Confirmed baseline `make ios-build` succeeds. Filled `request.md` and `plan.md`.

Deviations from plan: none.

---

### Step 4: CameraFrameSource protocol + CameraSessionManager conformance

**Status:** done

Created `CameraFrameSource.swift` protocol with `onPixelBuffer`, `start()`, `stop()`. Added `CameraFrameSource` to `CameraSessionManager`'s class declaration (additive — no existing code changed). Added `onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)?` as a stored public property; wired it in `captureOutput` alongside the existing `onFrame` callback. Kept file under 400 lines by avoiding a separate extension.

Deviations from plan: Used a stored property directly on the class (rather than a backing `_onPixelBuffer` property with a computed wrapper) after SwiftLint rejected the underscore identifier. Simpler and cleaner.

---

### Step 5: FixtureFrameSource + FixtureCameraViewController + scan route

**Status:** done

Created `FixtureFrameSource.swift` — decodes 3 curated fixture images (hand_held_card.jpg, IMG_1609.png, IMG_1610.png) from SPM bundle resources to `CVPixelBuffer` at 1920×1080 on init, emits on a `DispatchQueue` timer. Created `FixtureCameraViewController.swift` — parallel UIViewController (not a subclass of `CameraViewController`) using `UIImageView` + a hand-rolled overlay renderer that maps Vision normalized coordinates to the aspect-fit image rect. Created `FixtureCameraPreviewRepresentable.swift` as the SwiftUI bridge. Added `scan` case to `PreviewGalleryRootView`. Added 3 fixture images to `Resources/FixtureFrames/` and declared them in `Package.swift`. Created `FixtureFrameSourceTests.swift` covering pixel buffer dimensions, pixel format, frame emission, stop behavior, and sample buffer creation. Fixed two Swift 6 concurrency errors (`@MainActor` on test class, `nonisolated` on `makeSampleBuffer`). Fixed three SwiftLint violations (force unwraps, comma spacing). `make ios-snapshot ROUTE=scan` produces a PNG of a fixture MTG card; detection overlay appears on subsequent launches.

Deviations from plan: `FixtureCameraViewController` uses its own overlay renderer (not `DetectionOverlayRenderer`) because `DetectionOverlayRenderer.update()` requires an `AVCaptureVideoPreviewLayer` for coordinate conversion — unavailable without AVFoundation. The custom renderer is simpler and maps Vision coordinates directly to the aspect-fit image bounds.

---

### Step 6: Documentation

**Status:** done

Added "UI iteration for agents" section to `apps/ios/CLAUDE.md` covering: how to run snapshots, where PNGs land, how to add routes, how the camera fixture works. Added `make ios-snapshot` and `make ios-snapshot-all` to the Development commands in root `CLAUDE.md`.

Deviations from plan: none.

---

### Step 7: Verification

**Status:** done

- `make ios-build` — BUILD SUCCEEDED (baseline and after all changes).
- `make ios-snapshot ROUTE=settings` — PNG shows full SettingsView with API URL, toggles, sliders.
- `make ios-snapshot ROUTE=scan` — PNG shows fixture MTG card image (Daybreak Coronet, Dig Through Time, etc.) cycling on a black background; detection overlay (green quad) appears within the first several seconds.
- `make ios-test` — TEST SUCCEEDED (all tests pass including new FixtureFrameSourceTests).
- `make ios-lint` — 10 violations found, all in pre-existing files not touched by this effort (AppModel.swift, AutoScanViewModel.swift, CardDetectionEngine.swift, RectangleFilter.swift, RecognitionQueueTests.swift, ScanYOLOSupportTests.swift, RectangleFilterTests.swift). Zero new violations introduced.

Deviations from plan: none.

---

### Step 3: Preview host wiring (MTGScannerApp + PreviewGalleryRootView)

**Status:** done

Created `PreviewGalleryRootView.swift` with `settings` route (renders `SettingsView` in a `NavigationStack` with a fresh `AppModel`) and a default "Unknown route" fallback that tells the agent exactly which file to edit. Added `#Preview` blocks for both `settings` and `scan (placeholder)`. Updated `MTGScannerApp.swift` with a `#if DEBUG` guard that reads `UserDefaults.standard.string(forKey: "UI_PREVIEW_ROUTE")` and swaps `RootTabView` for `PreviewGalleryRootView(route:)`. Extracted `rootTabView` as a computed property to keep the `#else` branch DRY. Ran `make ios-snapshot ROUTE=settings` — PNG shows full `SettingsView` with API URL, toggles, sliders. Ran `ROUTE=scan` — shows "Unknown route: scan" placeholder as expected. Build succeeded.

Deviations from plan: none.

---

### Step 2: Screenshot harness (scripts/ios-screenshot.sh + Makefile)

**Status:** done

Created `scripts/ios-screenshot.sh` — resolves simulator UDID (prefers booted, falls back to first available), boots if needed, installs the built `.app`, launches with `-UI_PREVIEW_ROUTE <route>` argument, waits `IOS_SNAPSHOT_WAIT` seconds (default 3), captures PNG via `xcrun simctl io screenshot`, terminates the app. Output goes to `services/.artifacts/ui-snapshots/<route>.png`. Added `ios-snapshot` and `ios-snapshot-all` Makefile targets. Added `services/.artifacts/` to `.gitignore`. Ran `ROUTE=settings ./scripts/ios-screenshot.sh settings` against the unmodified app — PNG captured successfully (shows `RootTabView` with camera blank, tab bar visible). Harness confirmed working.

Deviations from plan: none.

---

