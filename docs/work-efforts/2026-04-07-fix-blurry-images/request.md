# Request: Fix Blurry Scan Captures

**Date:** 2026-04-07
**Author:** Brett Vitaz

## Goal

Images captured from scan mode are blurry enough that the API has trouble identifying Magic cards. Investigate the camera capture pipeline and propose then implement a fix that improves still-photo sharpness without regressing live card detection.

## Requirements

1. Investigate autofocus locking and focus behavior during still capture.
2. Investigate captured image resolution, JPEG encoding, cropping, and upload paths to confirm whether the app is downscaling or over-compressing images.
3. Identify the likely root cause and implement the camera-side changes needed to improve scan capture sharpness.
4. Preserve real-time scan performance and the existing capture serialization safeguards.
5. Verify the change with iOS tests and linting.

## Scope

**In scope:**
- iOS camera device selection, autofocus, auto-exposure, still-photo capture settings, and related unit tests.
- Review of crop/upload encoding paths to distinguish focus problems from resolution/compression problems.

**Out of scope:**
- Backend recognition prompt changes.
- API schema or endpoint changes.
- Server-side image sharpening or preprocessing.
- Manual on-device capture validation beyond identifying it as a recommended follow-up.

## Verification

Run the iOS test and lint targets:

- `make ios-test`
- `make ios-lint`
- `git diff --check`

Manual follow-up: capture cards on a physical device at normal scan distance and scanning-station distance, then inspect the uploaded/cropped artifacts for text sharpness and API recognition quality.

## Context

Files or docs the agent should read before starting:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraSessionManager.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraViewController.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanViewModel.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/RecognitionQueue.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Services/CardCropService.swift`
- `docs/work-efforts/2026-04-06-fix-split-cards/handoff-blurry-images.md`

## Notes

- The live video session preset should remain `.hd1920x1080` because it feeds real-time Vision/Core ML detection.
- Still-photo capture should remain full-resolution and should not be replaced with video-frame capture.
