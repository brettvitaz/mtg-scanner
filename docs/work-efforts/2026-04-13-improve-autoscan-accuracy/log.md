# Log: Improve Auto-Scan Accuracy with Adaptive Detection Window

## Progress

### Step 1: Core detection zone implementation

**Status:** done

Implemented the core detection zone filtering system:

- Created `DetectionZone.swift` with containment, size (≥40% area), and portrait aspect ratio filtering
- Updated `CardPresenceTracker.swift` to add `detectionZone` property and filtering logic
- Added `calibrate(from:)` and `resetZone()` methods to `CardPresenceTracker`

### Step 2: Zone overlay and UI wiring

**Status:** done

- Added zone boundary overlay to `DetectionOverlayRenderer` with dashed blue line style
- Updated `CameraViewController` with `detectionZone` property and `updateZoneOverlay()` method
- Updated `CameraPreviewRepresentable` to pass `detectionZone`
- Added `isCalibrated` state to `AutoScanViewModel`

### Step 3: Settings UI and state management

**Status:** done

- Added "Reset Detection Zone" button to SettingsView
- Wired zone reset through Environment key (`cardDetectionZoneReset`)
- Updated `AutoScanViewModel.stop()` to reset zone and `isCalibrated` state
- Added `resetDetectionZone()` public method

### Step 4: Tests and build verification

**Status:** done

- Created `DetectionZoneTests.swift` with comprehensive unit tests
- Updated `DetectionOverlayRendererTests.swift` to account for new zone overlay layer
- Build passes: `make ios-build` ✓
- SwiftLint passes: `make ios-lint` ✓

---

### Step 5: Test fixes and final verification

**Status:** done

Fixed two failing `DetectionZoneTests` with incorrect test data:
- `testCombinedFilterFailsOnAspect`: Changed box from 0.6×0.6 (area 0.36) to 0.75×0.75 (area 0.5625) — the smaller box failed `isLargeEnough` instead of `isPortraitAspect`
- `testCombinedFilterFailsOnSize`: Changed box from (0.45, 0.45, 0.3, 0.5) to (0.25, 0.25, 0.35, 0.55) — the original box was outside the effective zone, not just too small

All 22 `DetectionZoneTests` now pass. Full test suite passes. SwiftLint passes with 0 violations.

**Deviations from plan:** 
- The settings reset button works through Environment key instead of callback parameter (cleaner SwiftUI pattern)
- Zone overlay layer added as first sublayer, affecting existing test expectations

