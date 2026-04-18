# Plan: Improve Auto-Scan Accuracy with Adaptive Detection Window

**Planned by:** big-pickle
**Date:** 2026-04-13

## Approach

Improve auto-scan accuracy by implementing an adaptive detection window that calibrates from the first successful scan. After initial calibration, the system uses the detected card's position and size to define a reference zone for future detections. This approach accounts for different mounting solutions by learning the optimal detection area per session.

The detection zone enforces three constraints on all detected cards:
1. **Full containment** — the card must be entirely within the detection zone
2. **Size threshold** — the card must cover ≥40% of the frame area
3. **Portrait aspect ratio** — cards must be in portrait orientation

A visual overlay shows the detection zone boundary during auto-scan mode.

## Implementation Steps

1. **Create `DetectionZone.swift`** — New model with `referenceRect`, `tolerance`, and filtering methods (`contains`, `isLargeEnough`, `isPortraitAspect`)

2. **Update `CardPresenceTracker`** — Add `detectionZone` property, `calibrate(from:)` method, and apply zone filtering (containment, size, aspect) before firing new-card signals

3. **Update `CardDetectionEngine`** — Pass `detectionZone` to `CardPresenceTracker` in auto mode; filter YOLO results through zone

4. **Add zone overlay to `DetectionOverlayRenderer`** — New `updateZoneOverlay(zone:previewLayer:)` method drawing a dashed rectangle boundary (always visible in auto-scan mode)

5. **Add Settings controls** — "Reset Zone Calibration" button in Auto Scan section; status label showing current calibration state

6. **Update `AutoScanViewModel`** — On `stop()`, reset zone to nil (session-only behavior); wire zone to `presenceTracker`

## Files to Modify

| File | Change |
|------|--------|
| `Features/CardDetection/Detection/DetectionZone.swift` | **New** — DetectionZone model |
| `Features/CardDetection/Detection/CardPresenceTracker.swift` | Zone filtering + calibration |
| `Features/CardDetection/Detection/CardDetectionEngine.swift` | Zone passthrough |
| `Features/CardDetection/Overlay/DetectionOverlayRenderer.swift` | Zone boundary overlay |
| `Features/Settings/SettingsView.swift` | Reset calibration UI |
| `Features/AutoScan/AutoScanViewModel.swift` | Zone lifecycle management |
| `Tests/.../CardPresenceTrackerTests.swift` | Add zone filtering tests |
| `Tests/.../DetectionZoneTests.swift` | **New** — DetectionZone unit tests |

## Risks and Open Questions

- **Calibration timing**: The first scan's bounding box is captured post-capture via `detectBestBox()`. Need to ensure this returns valid data reliably.
- **Edge cases**: What if the first scan has a poor bounding box? Consider adding a minimum quality threshold for calibration.
- **Coordinate space**: YOLO returns top-left origin boxes; Vision uses bottom-left. Must handle conversion consistently in `DetectionZone.contains()`.

## Verification Plan

1. **Build**: `make ios-build` — must compile without errors
2. **Tests**: `make ios-test` — new `DetectionZoneTests` and updated `CardPresenceTrackerTests` must pass
3. **Manual testing**:
   - Start auto-scan, observe dashed zone overlay appears
   - Place card near edge — should NOT trigger capture
   - Place card in center (covering ≥40% frame) — triggers after settle delay
   - After successful capture, zone recalibrates to new position
   - Stop and restart auto-scan — zone resets to default (session-only)
   - Tap "Reset Zone Calibration" — returns to default zone
