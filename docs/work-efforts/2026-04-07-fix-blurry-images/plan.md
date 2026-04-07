# Plan: Fix Blurry Scan Captures

**Planned by:** Codex
**Date:** 2026-04-07

## Approach

Trace the camera capture path from `CameraSessionManager` through crop/upload encoding to determine whether blur is caused by focus timing, capture resolution, or downstream image processing. Keep `.hd1920x1080` for live video detection, but improve still-photo capture by selecting a better back camera when available, waiting for focus/exposure to settle, and preserving max-resolution photo settings. Add targeted unit coverage for deterministic helper logic and verify with the iOS test and lint targets.

## Implementation Steps

1. Inspect capture setup, autofocus configuration, photo output settings, crop helpers, and upload JPEG encoding.
2. Update `CameraSessionManager` to prefer virtual multi-camera back devices before falling back to wide angle, while keeping the existing session preset.
3. Replace the fixed autofocus delay with a focus/exposure settle loop that captures when stable or after a bounded timeout.
4. Preserve full-resolution capture by selecting the largest supported photo dimensions by pixel area and requesting quality-prioritized photo capture when supported.
5. Restore continuous autofocus and auto-exposure after each capture, keeping the existing in-flight and stale-handler safeguards.
6. Add unit tests for preferred camera ordering and largest-photo-dimension selection.
7. Run `make ios-test`, `make ios-lint`, and `git diff --check`.

Steps 2-5 are in the same file and should be implemented together. Step 6 depends on the helper APIs introduced in steps 2 and 4.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraSessionManager.swift` | Improve camera device selection, focus/exposure settle behavior, and still-photo quality settings. |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CameraSessionManagerTests.swift` | Add unit coverage for camera preference ordering and max photo dimension selection. |

## Risks and Open Questions

- Focus/exposure settling depends on real camera hardware; simulator tests can validate code paths and helper logic but cannot prove physical sharpness.
- Virtual camera availability varies by iPhone model, so the device selection must retain a wide-angle fallback.
- The capture settle timeout is intentionally bounded at `1.2s` to avoid hanging capture if hardware never reports stable focus/exposure.
- The camera manager was already close to the SwiftLint type body length limit; any added code should either remain localized or justify a scoped lint suppression.

## Verification Plan

Run:

- `make ios-test`
- `make ios-lint`
- `git diff --check`

Also note that `swift test` is not an appropriate final verifier for this iOS package in the current environment because it builds for macOS and cannot import `UIKit`.
