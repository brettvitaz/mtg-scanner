# Review: Torch and Scan Mode Redesign

**Reviewed by:** Codex
**Date:** 2026-04-06

## Summary

**What was requested:** Redesign the iOS scan screen controls by moving Scan/Auto mode selection to the Scan tab, replacing the ellipsis menu with a flashlight control, removing Binder mode, and renaming Quick Scan to Auto Scan.

**What was delivered:** The Scan tab now owns mode selection and presents a Scan/Auto picker on tab reselection; the scan overlays use a dedicated flashlight button with brightness controls; Binder mode was removed from active modes; Quick Scan source/tests/settings were renamed to Auto Scan; and torch state now turns off on Scan tab exit while preserving the previous level for the next explicit toggle.

**Deferred items:** Manual physical-device validation of the actual torch hardware remains recommended because simulator tests cannot exercise the camera torch.

## Code Review Checklist

Evaluate each criterion against the changes made. State pass or fail with brief evidence.

### 1. Correctness

**Result:** pass

The implementation matches the requirements: Scan and Auto are the only selectable modes, the Scan tab reselect opens the mode picker, Binder is absent from active mode selection, and the bottom-right control is a flashlight button. Follow-up bugs were addressed by using a real `UITabBar` tap recognizer for Scan tab reselection, clearing live torch state on Scan tab exit, and leaving the torch off on return while preserving the previous brightness for toggle-on.

### 2. Simplicity

**Result:** pass

The main abstractions are direct and bounded: `FlashlightButton` owns only flashlight UI behavior, `RootTabView` owns mode selection, `ScanView` owns scan activity/torch binding state, and `CameraViewController` owns camera visibility and hardware torch application. The UIKit tab observer is localized to `RootTabView` because SwiftUI does not provide a direct tab reselect hook.

### 3. No Scope Creep

**Result:** pass

Changes are limited to the requested scan mode, torch control, Binder removal, and Quick Scan to Auto Scan rename. Backend APIs, recognition accuracy, and user data migration were not changed.

### 4. Tests

**Result:** pass

Unit tests were updated or renamed for `DetectionMode`, Auto Scan behavior, settings keys, crop helper behavior, and flashlight logic. The app scheme still reports 0 executed tests, so `MTGScannerKitTests` was run directly and passed.

### 5. Safety

**Result:** pass

No force unwraps or destructive state resets were added. Torch hardware calls remain gated through `CameraSessionManager`, and the Scan tab return path now leaves the live torch binding at `0` so the camera controller keeps hardware off until the user toggles. The tab recognizer is passive with `cancelsTouchesInView = false` and simultaneous recognition enabled.

### 6. API Contract

**Result:** not applicable

No backend response schema or API contract was changed. The rename from Quick Scan to Auto Scan is internal iOS source/test/settings work, with old `quick_scan_*` settings intentionally ignored per requirement.

### 7. Artifacts and Observability

**Result:** pass

Project references were updated for renamed files, and no debug artifacts or generated outputs were committed. The work-effort docs now record the follow-up fixes and the known app-scheme 0-test behavior.

### 8. Static Analysis

**Result:** pass

`make ios-lint` passed with 0 violations. `git diff --check` passed.

## Verification Results

Commands run:

```bash
make ios-lint
make ios-test
xcodebuild test -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScannerKitTests -destination 'id=4B11588E-6F6B-4E04-8DC1-876BCA58C024' ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
git diff --check
```

Results:

- `make ios-lint`: passed with 0 violations.
- `make ios-test`: succeeded; the app scheme still executed 0 tests.
- `MTGScannerKitTests`: succeeded.
- `git diff --check`: succeeded.

Manual verification reported during the effort:

- Initial Scan tab reselect implementation did not present the menu; fixed by replacing the delegate observer with a passive tab bar tap recognizer.
- Flashlight icon could remain yellow after leaving Scan; fixed by clearing the scan torch binding when the Scan tab becomes inactive.
- The desired behavior later changed: returning to Scan should not turn the flashlight back on automatically, but should preserve the previous level for the next explicit toggle.

## Notes

The `docs/work-efforts/2026-04-06-torch-scan-redesign-codex/` directory was initially untracked and contained only template files. This documentation was filled out after implementation, so it records the final delivered state rather than the exact minute-by-minute sequence from the original coding session.
