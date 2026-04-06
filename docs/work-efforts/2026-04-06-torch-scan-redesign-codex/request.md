# Request: Torch and Scan Mode Redesign

**Date:** 2026-04-06
**Author:** Brett

## Goal

Redesign the iOS scan screen controls so scan mode selection lives on the Scan tab and the bottom-right camera control is dedicated to flashlight control. Remove Binder mode from the active scanning UI and rename Quick Scan concepts to Auto Scan where practical.

## Requirements

1. Replace the bottom-right ellipsis scan menu with a dedicated flashlight button for Scan and Auto modes.
2. Move Scan/Auto mode selection to the Scan tab; tapping the already-active Scan tab should present a mode picker.
3. Remove Binder mode from active detection modes, mode tests, engine switching, and user-visible copy.
4. Rename Quick Scan concepts broadly to Auto Scan, including files, types, settings keys, comments, and tests where practical.
5. Use new `auto_scan_*` UserDefaults keys only; do not migrate old `quick_scan_*` settings.
6. Persist the previous torch level for the current app session through `AppModel.lastTorchLevel`, with default toggle-on level `0.5`.
7. Turn the torch off when the scan view is left or the app backgrounds, while keeping the previous level for the next explicit flashlight toggle.
8. Long-pressing the flashlight should open a brightness popover; brightness should snap to 1%, 10%, 25%, 50%, 75%, and 100% within a 3% threshold.
9. Keep the bottom bar layout as `[Photo] [Shutter or Start/Stop] [Flashlight]`.
10. Maintain accessibility labels, hints, and values for the flashlight and scan mode picker.

## Scope

**In scope:**
- iOS scan tab UI and mode selection.
- Torch button UI, brightness popover, and torch state handoff to the camera controller.
- Detection mode model and tests.
- Quick Scan to Auto Scan rename across iOS source, tests, docs, and project references.
- Removal of Binder mode from active detection routing.

**Out of scope:**
- Backend API changes.
- Recognition accuracy or model changes.
- Migration of old Quick Scan settings keys.
- Collection names or user data containing the word "Binder" or "Quick Scan".
- A full custom tab bar rewrite.

## Verification

Run:

```bash
make ios-lint
make ios-test
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'id=4B11588E-6F6B-4E04-8DC1-876BCA58C024' ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
git diff --check
```

Manual checks:

- Tap the active Scan tab and verify the Scan/Auto mode picker appears.
- Switch from Scan to Results and back with the torch on; verify the flashlight stays off and the icon remains inactive.
- Toggle the flashlight on after returning to Scan; verify it returns to the previous brightness level.
- Background and foreground the app with the torch on; verify torch turns off and does not unexpectedly resume from background alone.
- Tap and long-press the flashlight; verify toggle, popover, snapping, and accessibility text.
- Confirm Binder is not available as a scan mode and Quick Scan user-facing labels now say Auto Scan.

## Context

Files or docs the agent should read before starting:

- `/Users/brettvitaz/Development/mtg-scanner/tmp/torch-plan.md`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/RootTabView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanMenuButton.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Models/DetectionMode.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraViewController.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraPreviewRepresentable.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/QuickScan/`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/`

## Notes

The work included follow-up fixes after initial implementation: replacing the tab reselect observer with a reliable `UITabBar` tap recognizer, clearing torch UI state when leaving the Scan tab, and changing tab-return behavior so the previous brightness is retained but not automatically re-enabled.
