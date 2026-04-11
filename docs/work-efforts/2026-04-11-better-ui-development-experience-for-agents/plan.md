# Plan: Better UI Development Experience for Agents

**Planned by:** claude-sonnet-4-6
**Date:** 2026-04-11

## Approach

Build a three-layer system that lets an agent run `make ios-snapshot ROUTE=<name>` and get a PNG of the named view in `services/.artifacts/ui-snapshots/`. Layer 1 is a shell harness (`scripts/ios-screenshot.sh`) that boots the simulator, installs the app, launches it with a launch argument, waits for UI to settle, screenshots via `simctl io`, and terminates cleanly. Layer 2 is a debug-only `PreviewGalleryRootView` in the app that reads the launch arg and swaps the tab root for the named route. Layer 3 is a `FixtureCameraViewController` (a `CameraFrameSource`-driven parallel of `CameraViewController`) that uses fixture card images instead of AVFoundation, allowing `ScanView` to render and run detection in the Simulator.

## Implementation Steps

1. **Fill work-effort templates** — `request.md` and `plan.md` before any code. *(This file.)*
2. **Screenshot harness** — `scripts/ios-screenshot.sh` + `ios-snapshot` / `ios-snapshot-all` Makefile targets. Verify independently with the unmodified app.
3. **Preview host** — `#if DEBUG` launch arg guard in `MTGScannerApp.swift`; new `PreviewGalleryRootView.swift` with `settings` route and `#Preview` blocks.
4. **CameraFrameSource seam** — `CameraFrameSource.swift` protocol; `CameraSessionManager` adopts it additively; `CameraViewController` wired through the protocol where it feeds frames to the engine.
5. **Fixture frame source + scan route** — `FixtureFrameSource.swift`, `FixtureCameraViewController.swift`; `scan` route in `PreviewGalleryRootView`; fixture images added as SPM resources; `FixtureFrameSourceTests`.
6. **Documentation** — `apps/ios/CLAUDE.md` new section; root `CLAUDE.md` link.
7. **Review and log** — fill `review.md`, append final `log.md` entries.

Steps 2 and 3 are independent (harness needs no Swift changes; preview host needs no harness). Step 4 and 5 depend on 3 (route must exist to wire). Step 6 depends on 5 (describes the finished system). Step 7 runs after all others.

## Files to Modify

| File | Change |
|------|--------|
| `scripts/ios-screenshot.sh` | **new** — simctl boot/install/launch/screenshot/terminate |
| `Makefile` | add `ios-snapshot`, `ios-snapshot-all` |
| `apps/ios/MTGScanner/App/MTGScannerApp.swift` | `#if DEBUG` block to read `UI_PREVIEW_ROUTE` and swap root |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/PreviewGalleryRootView.swift` | **new** — route switch + `#Preview` blocks |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraFrameSource.swift` | **new** — protocol |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraSessionManager.swift` | conform to `CameraFrameSource` (additive only) |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/FixtureFrameSource.swift` | **new** — `CVPixelBuffer` emitter from fixture images |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/FixtureCameraViewController.swift` | **new** — UIViewController for preview mode (UIImageView + detection) |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/FixtureCameraPreviewRepresentable.swift` | **new** — `UIViewControllerRepresentable` for `FixtureCameraViewController` |
| `apps/ios/MTGScannerKit/Package.swift` | add fixture image resources |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Resources/FixtureFrames/` | **new** — 3 curated images from `samples/test/` |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/FixtureFrameSourceTests.swift` | **new** — pixel buffer dimension + rate tests |
| `.gitignore` | verify `services/.artifacts/ui-snapshots/` excluded |
| `apps/ios/CLAUDE.md` | add "UI iteration for agents" section |
| `CLAUDE.md` (root) | add link in Development commands |

## Risks and Open Questions

- `CameraViewController.setupPreviewLayer()` binds an `AVCaptureVideoPreviewLayer` to `sessionManager.session` — the fixture path cannot reuse this. `FixtureCameraViewController` is therefore a parallel type (not a subclass), using `UIImageView` as the background layer. This was confirmed by reading the source; it is the expected approach.
- `CardDetectionEngine.processFrame(_:)` accepts a `CMSampleBuffer`. The fixture source must wrap `CVPixelBuffer` in a `CMSampleBuffer` for compatibility with the engine. This is straightforward with `CMSampleBufferCreateReadyWithImageBuffer`.
- Screenshot timing: start with a 2-second `sleep` after launch; increase to 3 if overlays are not consistently captured on the first try.
- `CODE_SIGNING_ALLOWED=NO` must be passed to `ios-snapshot` build just as it is in `ios-test`; the `.app` path is extracted from `xcodebuild -showBuildSettings` to avoid hardcoding DerivedData.

## Verification Plan

1. `make ios-build` — baseline passes (confirmed before implementation).
2. After Step 2: `make ios-snapshot ROUTE=settings` without Swift changes → PNG of `RootTabView` confirms harness works.
3. After Step 3: same command → PNG shows `SettingsView` at root. `make ios-snapshot ROUTE=scan` falls through to placeholder.
4. After Step 5: `make ios-snapshot ROUTE=scan` → PNG shows `ScanView` with detection overlay on a fixture card image.
5. `make ios-test` — no regressions.
6. `make ios-lint` — clean.
