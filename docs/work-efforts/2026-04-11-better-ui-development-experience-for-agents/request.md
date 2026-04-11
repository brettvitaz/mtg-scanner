# Request: Better UI Development Experience for Agents

**Date:** 2026-04-11
**Author:** Brett Vitaz

## Goal

Enable coding agents to see and interact with UI changes they make to the iOS app. Today the project has no `#Preview` blocks, no screenshot tooling, and its core camera screens cannot run in the Simulator. Agents write SwiftUI blind and cannot verify their changes.

## Requirements

1. Agents must be able to capture a PNG screenshot of any named UI route from the command line without opening Xcode.
2. The screenshot loop must work for non-camera views (e.g. Settings) with real app data.
3. The screenshot loop must work for camera views (e.g. ScanView) in the Simulator using fixture card images in place of the live camera, with the real detection and overlay pipeline running.
4. A single `make ios-snapshot ROUTE=<name>` command must produce the PNG end-to-end.
5. Production app builds must be completely unaffected — no preview code in release builds.
6. Future agents must be able to discover and use the loop via documentation in `apps/ios/CLAUDE.md`.

## Scope

**In scope:**
- `scripts/ios-screenshot.sh` — simctl boot/install/launch/screenshot/terminate harness
- `make ios-snapshot` and `make ios-snapshot-all` Makefile targets
- `PreviewGalleryRootView` — debug-only route switch, replaces `RootTabView` when `UI_PREVIEW_ROUTE` launch arg is present
- `#if DEBUG` guard in `MTGScannerApp.swift` to read the launch arg
- `settings` route — `SettingsView` with real `AppModel`
- `scan` route — `ScanView` with `FixtureCameraViewController` (UIImageView backdrop + fixture `CVPixelBuffer` detection)
- `CameraFrameSource` protocol — minimum seam between `CameraViewController` and fixture implementation
- `FixtureFrameSource` — emits `CVPixelBuffer`s from `samples/test/` images on a timer
- `FixtureCameraViewController` — parallel UIViewController for preview mode (not a subclass of `CameraViewController`)
- `FixtureFrameSourceTests` — unit tests for pixel buffer dimensions and emission rate
- Documentation updates in `apps/ios/CLAUDE.md` and root `CLAUDE.md`

**Out of scope:**
- Previews or fakes for `ResultsView`, `LibraryView`, `CardDetailView`, `CorrectionView`, `AutoScanView`, or shared components (follow-up)
- XCUITest target or CI integration
- Snapshot diffing library (e.g. swift-snapshot-testing)
- MCP server wrapping simctl

## Verification

1. `make ios-build` passes (baseline and after changes).
2. `make ios-snapshot ROUTE=settings` produces `services/.artifacts/ui-snapshots/settings.png` showing `SettingsView`.
3. `make ios-snapshot ROUTE=scan` produces `services/.artifacts/ui-snapshots/scan.png` showing `ScanView` with at least one detection overlay drawn on a fixture card image.
4. `make ios-test` passes — no regressions from protocol additions.
5. `make ios-lint` passes — no new lint suppressions.

## Context

Files to read before starting:
- `apps/ios/MTGScanner/App/MTGScannerApp.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/RootTabView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraViewController.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraSessionManager.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraPreviewRepresentable.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/ViewModels/CardDetectionViewModel.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift`
- `Makefile`
