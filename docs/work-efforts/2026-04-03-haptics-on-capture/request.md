# Request: Add haptic feedback to capture interface

**Date:** 2026-04-03
**Author:** brettvitaz

## Goal

Add haptic feedback when the scan interface captures an image, change the shutter sound to a softer camera-like click, and ensure Quick Scan auto-capture also provides haptic feedback.

## Requirements

1. Fire a haptic tap when the scan interface captures an image
2. Change shutter sound to a very small click or beep (camera-like, not obtrusive)
3. Quick Scan auto-capture should also have haptic feedback

## Scope

**In scope:**
- Modify manual capture path (ScanView) to change sound and keep existing haptic
- Modify Quick Scan auto-capture path (QuickScanViewModel) to add haptic feedback
- Build and lint verification

**Out of scope:**
- Adding new haptic patterns or intensities beyond what's specified
- Modifying capture flow logic or detection algorithms
- Adding UI settings for haptic/sound preferences

## Verification

1. Build the iOS app: `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`
2. Run SwiftLint: `make ios-lint`
3. Both commands should pass successfully

## Context

Files to modify:
- apps/ios/MTGScanner/Features/Scan/ScanView.swift
- apps/ios/MTGScanner/Features/QuickScan/QuickScanViewModel.swift

Existing haptic usage: Currently only ScanView.triggerShutterFeedback() fires haptic feedback with UIImpactFeedbackGenerator(style: .medium). Quick Scan auto-capture has no haptic.

## Notes

- System sound 1108 is the full camera shutter sound; 1306 is a softer click
- Quick Scan should use lighter haptic (.light) since it's automatic and shouldn't be jarring
- Current haptic implementation uses UIImpactFeedbackGenerator directly inline
