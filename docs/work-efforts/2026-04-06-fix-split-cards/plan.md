# Plan: Fix Blurry Images from iOS Camera

**Planned by:** claude-sonnet-4-6
**Date:** 2026-04-07

## Approach

Add autofocus configuration to `CameraSessionManager` so captured photos are sharp. During session setup, configure `.continuousAutoFocus` with a center focus point and `.near` range restriction. Before each photo capture, trigger a single `.autoFocus` pass, wait 0.3s for it to settle, capture, then restore continuous autofocus.

## Implementation Steps

1. Add `configureFocus(_ device:)` private method to `CameraSessionManager` and call it from `configureOnSessionQueue()` after `captureDevice = device`.
2. Refactor `capturePhoto()` to enqueue focus-then-capture logic on `sessionQueue`.
3. Add private helpers `lockFocusThenCapture()`, `captureWithCurrentSettings()`, and `restoreContinuousAutoFocus()`.

Steps 2 and 3 are done together — they are a single logical refactor of the capture path.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraSessionManager.swift` | Add focus configuration on setup; refactor capturePhoto to lock focus before capture |

## Risks and Open Questions

- The 0.3s delay is a heuristic. On some devices focus may settle faster or slower, but this is the value specified in the handoff.
- `.autoFocus` may not be supported on all devices; fallback to immediate capture is handled.

## Verification Plan

- `make ios-build` — confirm the app compiles
- `make ios-test` — confirm existing tests pass
