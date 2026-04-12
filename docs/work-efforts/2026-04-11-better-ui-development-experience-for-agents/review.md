# Review: Better UI Development Experience for Agents

**Reviewed by:** claude-sonnet-4-6
**Date:** 2026-04-11

## Summary

**What was requested:** Build a `make ios-snapshot ROUTE=<name>` loop so coding agents can see PNG screenshots of named UI views (including camera views via fixture images) without opening Xcode.

**What was delivered:** Full end-to-end loop: `scripts/ios-screenshot.sh` harness + Makefile targets, `PreviewGalleryRootView` debug-only route host in the app, `settings` route (SettingsView), `scan` route (FixtureCameraViewController with real CardDetectionEngine running on fixture card images), `CameraFrameSource` protocol, `FixtureFrameSource`, `FixtureFrameSourceTests`, documentation in both CLAUDE.md files.

**Deferred items:** Previews/routes for ResultsView, LibraryView, CardDetailView, CorrectionView, AutoScanView, and shared components — deferred by design (pilot scope).

## Code Review Checklist

### 1. Correctness

**Result:** pass

- `scripts/ios-screenshot.sh`: resolves UDID (prefers booted, falls back to first available), boots simulator, installs app, launches with `-UI_PREVIEW_ROUTE` argument, waits configurable duration, screenshots, terminates. Tested end-to-end — both routes produce correct PNGs.
- `PreviewGalleryRootView`: reads `UserDefaults.standard.string(forKey: "UI_PREVIEW_ROUTE")` correctly via iOS's launch-argument-to-UserDefaults bridge. `#if DEBUG` guard prevents any preview code reaching release builds.
- `CameraFrameSource`: protocol correctly abstracts `onPixelBuffer`/`start()`/`stop()`. `CameraSessionManager` conformance is additive — existing `onFrame` wiring unchanged.
- `FixtureFrameSource`: images decoded to `CVPixelBuffer` at 1920×1080 (`kCVPixelFormatType_32BGRA`) matching production session preset. Timer-based emission at 5 Hz drives the real detection engine.
- `FixtureCameraViewController`: `makeSampleBuffer(from:)` uses `CMSampleBufferCreateReadyWithImageBuffer` correctly. Overlay coordinate mapping (Vision normalized → aspect-fit image rect) is correct: Y-flip applied (`1.0 - pt.y`), then scaled to the image bounds.
- Edge cases: `FixtureFrameSource.loadPixelBuffers()` uses `compactMap` — if an image fails to load, it is silently skipped (no crash). `FixtureCameraViewController.start()` guards `pixelBuffers.isEmpty`.

### 2. Simplicity

**Result:** pass

- All new functions are under 30 lines. Deepest nesting is 3 levels.
- `FixtureCameraViewController` is ~230 lines — above the 200-line soft limit but well within the 50-line per-function limit. The length is justified by UIKit lifecycle (viewDidLoad/viewDidAppear/viewWillDisappear/viewDidLayoutSubviews) plus the overlay renderer — splitting would create unnecessary indirection.
- `FixtureFrameSource` is self-contained: decode at init, emit on timer, no I/O on hot path.
- No unnecessary abstractions. `FixtureCameraPreviewRepresentable` is 20 lines.

### 3. No Scope Creep

**Result:** pass

- Only the two pilot routes (settings, scan) are wired. No previews added for other views.
- No XCUITest target, no snapshot-diffing library, no MCP server.
- `CameraSessionManager` change is strictly additive: one stored property + declaration in class header + two lines in `captureOutput`. Existing `onFrame` callback unchanged.
- No changes to production app flow. `RootTabView` path identical to before.

### 4. Tests

**Result:** pass

- `FixtureFrameSourceTests`: 5 tests covering pixel buffer width/height, pixel format (kCVPixelFormatType_32BGRA), frame emission (receives ≥1 frame after start), stop behavior (0 frames after stop), and `makeSampleBuffer` returning non-nil. All exercise real code paths — if implementations were deleted, tests would fail.
- `@MainActor` applied to test class for Swift 6 Sendable conformance.
- No force unwraps (SwiftLint `force_unwrapping` rule satisfied).

### 5. Safety

**Result:** pass

- No force unwraps in production code. `FixtureFrameSource.pixelBuffer(from:size:)` returns `nil` on every failure path via `guard`. `FixtureCameraViewController.makeSampleBuffer` is `nonisolated` (correct for a pure data factory).
- No retain cycles: `[weak self]` applied in all closures captured by long-lived objects (`frameSource.onPixelBuffer`, `engine.onDetection`).
- Threading: `FixtureFrameSource` emits on its own `DispatchQueue`. `FixtureCameraViewController.engine.onDetection` dispatches to `@MainActor` via `Task { @MainActor in }` per project rules. `FixtureCameraViewController` is a `UIViewController` subclass — lifecycle methods called on main thread by UIKit.
- `#if DEBUG` guard ensures no preview infrastructure in release builds.
- No secrets or credentials in code.

### 6. API Contract

**Result:** not applicable

Backend API contract unchanged. No schema modifications.

### 7. Artifacts and Observability

**Result:** not applicable

This effort adds observability tooling (screenshots) rather than changing recognition/detection behavior. The existing artifact pipeline is untouched. Detection engine used in fixture path produces the same `DetectedCard` structs as production.

### 8. Static Analysis

**Result:** pass

- `make ios-lint`: 10 violations found — all in files not touched by this effort (AppModel.swift, AutoScanViewModel.swift, CardDetectionEngine.swift, RectangleFilter.swift, RecognitionQueueTests.swift, ScanYOLOSupportTests.swift, RectangleFilterTests.swift). These are pre-existing issues confirmed by checking `git diff --name-only HEAD`.
- Zero new lint violations introduced. No SwiftLint suppressions added.
- `make ios-test`: TEST SUCCEEDED.
- `make ios-build`: BUILD SUCCEEDED.

## Verification Results

```
make ios-build          → BUILD SUCCEEDED (baseline and post-changes)
make ios-test           → TEST SUCCEEDED (including 5 new FixtureFrameSourceTests)
make ios-lint           → 10 violations (all pre-existing, zero introduced)
make ios-snapshot ROUTE=settings → services/.artifacts/ui-snapshots/settings.png
                                   shows SettingsView with API URL, toggles, sliders ✓
make ios-snapshot ROUTE=scan     → services/.artifacts/ui-snapshots/scan.png
                                   shows fixture MTG card image with detection overlay ✓
```

## Notes

- The `scan` route detection overlay appears within a few seconds of launch. Screenshot timing is set to 4s default; agents may set `IOS_SNAPSHOT_WAIT=8` to reliably capture an overlay frame.
- `FixtureCameraViewController` uses its own coordinate-mapping logic (Vision normalized → aspect-fit image bounds) instead of `DetectionOverlayRenderer`, which is tightly coupled to `AVCaptureVideoPreviewLayer`. This is the right call — no production code modified for this constraint.
- Pre-existing lint violations (10 total) are tracked as a separate scope item. They are not regressions from this effort.
- Follow-up: add routes for ResultsView, LibraryView, CardDetailView, CorrectionView, AutoScanView, and shared components. Pattern is established — each new route is 3–5 lines in `PreviewGalleryRootView.swift`.

## PR #66 Review Comment Resolution (2026-04-11)

All 11 reviewer comments addressed in 4 follow-up commits:

| # | File | Issue | Resolution |
|---|------|-------|------------|
| 1 | Makefile:59 | for-loop masks failures | Added `set -e;` prefix |
| 2 | ios-screenshot.sh:12 | Misleading "builds the app" comment | Fixed comment to say "Locates the pre-built .app" |
| 3 | ios-screenshot.sh:87 | BUILT_PRODUCTS_DIR multi-line; hardcoded app name | Added `exit` to awk; read FULL_PRODUCT_NAME from build settings |
| 4 | ios-screenshot.sh:112 | ROUTE not sanitized (path traversal) | Validate against `^[a-zA-Z0-9_-]+$` |
| 5 | FixtureFrameSource.swift:41 | start() creates duplicate timers | guard `!running, timer == nil` in queue.sync |
| 6 | FixtureFrameSource.swift:50 | stop() has no sync barrier | queue.sync sets running=false before returning |
| 7 | FixtureCameraViewController.swift:36 | frameQueue unused | Removed |
| 8 | FixtureFrameSourceTests.swift:43 | Data race on received var | Removed var; XCTestExpectation.fulfill() is thread-safe |
| 9 | FixtureFrameSourceTests.swift:56 | Flaky Thread.sleep test | Replaced with inverted expectation |
| 10 | PreviewGalleryRootView.swift:17 | Unused import SwiftData + libraryViewModel | Removed |
| 11 | Package.swift:21 | Fixture images ship in release builds | Moved to new MTGScannerFixtures SPM target |
