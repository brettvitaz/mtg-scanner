# Plan: Add haptic feedback to capture interface

**Planned by:** kimi-k2.5
**Date:** 2026-04-03

## Approach

Make two minimal changes to provide haptic feedback on both manual and auto-capture paths: (1) change the shutter sound ID in ScanView from 1108 to 1306 for a softer click, keeping the existing medium haptic; (2) add a light haptic call to QuickScanViewModel.triggerCapture() for auto-capture feedback. This satisfies all requirements with minimal code changes and no new abstractions.

## Implementation Steps

1. Update ScanView.swift line 194: change AudioServicesPlaySystemSound(1108) to 1306
2. Update QuickScanViewModel.swift: add UIImpactFeedbackGenerator(style: .light).impactOccurred() in triggerCapture() method
3. Verify build passes with xcodebuild
4. Verify SwiftLint passes

Steps 1 and 2 are independent and can be done in any order.

## Files to Modify

| File | Change |
|------|--------|
| apps/ios/MTGScanner/Features/Scan/ScanView.swift | Change AudioServicesPlaySystemSound(1108) to 1306 (softer click sound) |
| apps/ios/MTGScanner/Features/QuickScan/QuickScanViewModel.swift | Add UIImpactFeedbackGenerator(style: .light).impactOccurred() in triggerCapture() |

## Risks and Open Questions

- None identified. Changes are minimal and use well-established iOS APIs.

## Verification Plan

1. Run: `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`
2. Run: `make ios-lint`
3. Both should complete successfully with no errors
