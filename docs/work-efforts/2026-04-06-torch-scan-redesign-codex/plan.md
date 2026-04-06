# Plan: Torch and Scan Mode Redesign

**Planned by:** Codex
**Date:** 2026-04-06

## Approach

Implement the redesign by separating the two responsibilities that were previously combined in the scan menu: mode selection moves to the Scan tab, and flashlight control becomes a dedicated bottom-bar control. Hoist scan mode state to the tab root, reduce `DetectionMode` to Scan and Auto, and rename Quick Scan artifacts to Auto Scan. Keep the previous torch level in `AppModel.lastTorchLevel` for explicit toggle-on restore, but do not automatically re-enable the torch when returning to the Scan tab.

## Implementation Steps

1. Hoist `DetectionMode` into `RootTabView`, pass it into `ScanView`, and update the Scan tab label/icon from the selected mode.
2. Add a Scan/Auto picker sheet and install a non-interfering `UITabBar` tap observer that opens the picker only when the Scan tab was already selected at touch start.
3. Replace `ScanMenuButton` with a new `FlashlightButton` and brightness popover.
4. Implement torch toggle, last-level restore-on-toggle, popover long press, slider snapping, and accessibility value text.
5. Pass active-tab state into `ScanView`; on scan tab exit, store the current torch level, set the scan torch binding to `0`, and stop Auto Scan. On scan tab return, leave the torch off until the user explicitly toggles it on.
6. Cache `desiredTorchLevel` inside `CameraViewController`; apply it after `viewDidAppear` for normal torch state handoff, while preserving the new no-auto-reenable tab-return behavior by keeping the SwiftUI torch binding at `0`.
7. Reduce `DetectionMode` to `.scan` and `.auto`, update icons/display names, remove Binder detection routing, and update tests.
8. Rename Quick Scan source/tests to Auto Scan and update Xcode project references.
9. Rename settings keys to `auto_scan_*`, ignore old `quick_scan_*` keys, and update settings tests.
10. Run lint, app-scheme tests, package tests, and whitespace checks.

Step 6 depends on the tab active-state work in step 5 because it keeps the camera lifecycle handoff aligned with the SwiftUI torch binding. Steps 7 through 9 can be implemented in parallel with the flashlight UI as long as project references are reconciled before verification.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/RootTabView.swift` | Hoist scan mode state, add picker sheet, and install Scan tab reselect observer |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift` | Accept selected mode and active state, replace scan menu with flashlight, store previous torch level on exit, keep torch off on return, and stop Auto Scan |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/FlashlightButton.swift` | Add dedicated flashlight button, long-press popover, brightness snapping, and accessibility |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanMenuButton.swift` | Remove obsolete ellipsis scan menu |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraViewController.swift` | Cache desired torch level and apply it after the camera becomes visible |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraPreviewRepresentable.swift` | Pass renamed Auto Scan frame callback and torch level to the controller |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Models/DetectionMode.swift` | Reduce modes to Scan and Auto and update display names/icons |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/CardDetectionEngine.swift` | Remove Binder mode routing |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/ViewModels/CardDetectionViewModel.swift` | Remove obsolete detection mode state |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/QuickScan/` | Rename Quick Scan implementation to Auto Scan |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/` | Add renamed Auto Scan implementation files |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/AppModel.swift` | Rename Auto Scan settings keys and keep in-memory last torch level |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Settings/SettingsView.swift` | Update settings copy and bindings to Auto Scan |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/RecognitionBadgeView.swift` | Update Quick Scan copy to Auto Scan if present |
| `apps/ios/MTGScanner.xcodeproj/project.pbxproj` | Update file references for renamed/deleted/added Swift files |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/DetectedCardTests.swift` | Update detection mode tests |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/FlashlightButtonTests.swift` | Add or update torch logic tests |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanViewModelTests.swift` | Rename Quick Scan view model tests |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanCropHelperTests.swift` | Rename crop helper tests |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AppModelCropToggleTests.swift` | Verify new `auto_scan_*` keys and old key reset behavior |
| `apps/ios/CLAUDE.md` | Update iOS docs copy from Quick Scan to Auto Scan |

## Risks and Open Questions

- SwiftUI `TabView` does not provide a direct selected-tab reselect callback; a UIKit bridge is required. The observer must not block normal tab switching or present the picker when switching from another tab to Scan.
- Camera lifecycle ordering can drop torch updates if the SwiftUI state changes before `CameraViewController.viewDidAppear`; storing desired torch state in the controller keeps explicit torch updates reliable.
- Full Binder removal should remove active scan mode routing, but generic geometry helpers can remain if still tested and useful outside Binder mode.
- The old Quick Scan settings keys are intentionally ignored, so existing users will reset to Auto Scan defaults.
- Simulator verification cannot confirm physical torch hardware behavior; device testing is still valuable.

## Verification Plan

Run:

```bash
make ios-lint
make ios-test
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'id=4B11588E-6F6B-4E04-8DC1-876BCA58C024' ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
git diff --check
```

Manual verification should cover Scan tab reselect picker behavior, Scan-to-Results-to-Scan torch shutdown without auto-reenable, explicit flashlight toggle restoring the previous level, app background torch shutdown, flashlight tap/long-press behavior, and absence of Binder mode from the mode picker.
