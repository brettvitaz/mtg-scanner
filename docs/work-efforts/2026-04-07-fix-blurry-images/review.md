# Review: Fix Blurry Scan Captures

**Reviewed by:** Codex
**Date:** 2026-04-07

## Summary

**What was requested:** Investigate blurry images captured from scan mode, including autofocus locking and image resolution, then propose and implement a fix.

**What was delivered:** Improved the iOS still-photo capture path by preferring better back camera devices, waiting for autofocus/auto-exposure to settle before capture, preserving full-resolution settings, and adding targeted tests.

**Deferred items:** Manual physical-device validation remains a recommended follow-up because simulator tests cannot prove real camera sharpness.

## Code Review Checklist

Evaluate each criterion against the changes made. State pass or fail with brief evidence.

### 1. Correctness

**Result:** pass

The change addresses the likely root cause: capturing after a fixed autofocus delay rather than waiting for focus/exposure stability. It keeps full-resolution still capture, uses a bounded timeout to avoid hanging, and keeps existing stale-handler and in-flight capture protections.

### 2. Simplicity

**Result:** pass

The implementation stays localized to `CameraSessionManager` and adds only small helper methods for camera selection, photo dimension selection, point-of-interest configuration, and settle polling. Two scoped SwiftLint suppressions were used because the existing camera manager/test were already large and a structural refactor would exceed this task’s scope.

### 3. No Scope Creep

**Result:** pass

No backend API, prompt, schema, or server preprocessing changes were made. The changes are limited to iOS camera capture behavior and related unit tests.

### 4. Tests

**Result:** pass

Added tests for deterministic helper behavior: preferred back camera ordering and largest-photo-dimension selection. Existing capture state-machine tests continued to pass under the iOS simulator test target.

### 5. Safety

**Result:** pass

No force unwraps or secrets were introduced. Camera configuration remains on the serial session queue, capture completion remains serialized through the existing handler, and capture waiting is bounded by a timeout.

### 6. API Contract

**Result:** not applicable

No API routes, request/response schemas, or backend contracts changed.

### 7. Artifacts and Observability

**Result:** not applicable

No debug artifact pipeline changes were made. Existing uploaded image/crop paths remain unchanged except for improved source capture quality.

### 8. Static Analysis

**Result:** pass

`make ios-lint` passed with zero violations. The only new suppressions are scoped to the touched class/test body-length limits and are documented by their placement around the existing large code regions.

## Verification Results

- `make ios-test`: passed on iOS Simulator destination `iPhone 16 Pro`, with `** TEST SUCCEEDED **`.
- `make ios-lint`: passed with `SwiftLint passed.` and `Found 0 violations, 0 serious in 76 files.`
- `git diff --check`: passed with no output.
- `swift test`: attempted, but not used as final verification because it builds this package for macOS in the current environment and fails with `no such module 'UIKit'`.

## Notes

- Still-photo capture remains full-resolution; `.hd1920x1080` remains only for live video frames used by detection.
- Manual physical-device validation should compare card text sharpness and recognition quality at typical scan and scanning-station distances.
