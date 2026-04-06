# Log: Torch and Scan Mode Redesign

## Progress

### Step 1: Requirements Review and Clarifications

**Status:** done

Reviewed `/Users/brettvitaz/Development/mtg-scanner/tmp/torch-plan.md` and clarified the implementation plan. Confirmed that the work should remove Binder mode from active scan selection, rename Quick Scan to Auto Scan, replace the ellipsis menu with a flashlight control, and reset old Quick Scan settings rather than migrate them.

Deviations from plan: none

---

### Step 2: Scan Mode State and Tab Picker

**Status:** done

Moved selected scan mode state into `RootTabView`, passed it into `ScanView`, and made the Scan tab label/icon reflect the selected mode. Added a Scan/Auto picker sheet and later replaced the initial tab delegate observer with a passive `UITabBar` tap recognizer that only opens the picker when the Scan tab was already selected at touch start.

Files modified:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/RootTabView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift`

Deviations from plan: the initial `UITabBarControllerDelegate` bridge was replaced because it did not reliably receive Scan tab reselection events under SwiftUI `TabView`.

---

### Step 3: Flashlight Button and Brightness Controls

**Status:** done

Removed the old bottom-right scan menu and added `FlashlightButton` with tap-to-toggle, long-press brightness popover, yellow active state, accessibility label/hint/value, and brightness snapping at 1%, 10%, 25%, 50%, 75%, and 100%. Updated Scan and Auto overlays to use the flashlight control.

Files modified:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/FlashlightButton.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanMenuButton.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/FlashlightButtonTests.swift`

Deviations from plan: none

---

### Step 4: Torch State Lifecycle Fixes

**Status:** done

Added active-tab state from `RootTabView` into `ScanView`, storing the last torch level and clearing the torch binding when leaving the Scan tab. The behavior was later changed so returning to Scan keeps the flashlight off while preserving the previous level for the next explicit flashlight toggle.

Files modified:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/RootTabView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraViewController.swift`

Deviations from plan: after user feedback, tab return no longer re-enables the torch automatically.

---

### Step 9: Flashlight Return Behavior Change

**Status:** done

Updated `ScanView` so `onAppear` and the active-tab return path no longer restore `appModel.lastTorchLevel` into the live torch binding. Leaving Scan still stores the previous level and turns the torch off; tapping the flashlight later uses `FlashlightButton`'s existing restore-on-toggle behavior to return to the previous brightness.

Files modified:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift`
- `docs/work-efforts/2026-04-06-torch-scan-redesign-codex/`

Deviations from plan: intentional requirement change after implementation.

---

### Step 5: Detection Mode Cleanup and Binder Removal

**Status:** done

Reduced `DetectionMode` to `.scan` and `.auto`, updated display names and symbols, and removed the Binder detection branch from the active detection engine routing. Kept generic geometry helpers where still covered by standalone tests.

Files modified:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Models/DetectionMode.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/CardDetectionEngine.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/GridInterpolator.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/ViewModels/CardDetectionViewModel.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/DetectedCardTests.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/GridInterpolatorTests.swift`

Deviations from plan: `GridInterpolator` was retained as a generic helper because it remains independently tested.

---

### Step 6: Quick Scan to Auto Scan Rename

**Status:** done

Renamed Quick Scan files, types, tests, settings copy, and comments to Auto Scan. Updated Xcode project references for deleted Quick Scan files and new Auto Scan files.

Files modified:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/QuickScan/`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/QuickScanViewModelTests.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanViewModelTests.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/YOLOCropHelperTests.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AutoScanCropHelperTests.swift`
- `apps/ios/MTGScanner.xcodeproj/project.pbxproj`
- `apps/ios/CLAUDE.md`

Deviations from plan: none

---

### Step 7: Auto Scan Settings Keys

**Status:** done

Changed settings persistence to use `auto_scan_capture_delay` and `auto_scan_confidence_threshold`. Added tests confirming old `quick_scan_*` keys are ignored instead of migrated.

Files modified:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/App/AppModel.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Settings/SettingsView.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AppModelCropToggleTests.swift`

Deviations from plan: none

---

### Step 8: Verification

**Status:** done

Ran lint, app-scheme tests, package tests, and whitespace checks:

```bash
make ios-lint
make ios-test
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'id=4B11588E-6F6B-4E04-8DC1-876BCA58C024' ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
git diff --check
```

Results:

- `make ios-lint`: passed with 0 violations.
- `make ios-test`: passed; the app scheme still executed 0 tests.
- `MTGScannerKitTests` scheme: passed.
- `git diff --check`: passed.

Deviations from plan: ran the package test scheme directly because the app scheme reports 0 executed tests.

---
