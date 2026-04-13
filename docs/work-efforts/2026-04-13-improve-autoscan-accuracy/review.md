# Review: Improve Auto-Scan Accuracy with Adaptive Detection Window

**Reviewed by:** big-pickle (opencode agent)
**Date:** 2026-04-13

## Summary

**What was requested:** Improve auto-scan accuracy by implementing an adaptive detection window that calibrates from the first successful scan, filtering detections to require: (1) full containment within the zone, (2) minimum 40% frame area coverage, and (3) portrait aspect ratio. A visual dashed overlay shows the zone boundary during auto-scan mode. Session-only calibration (resets on app restart or manual reset).

**What was delivered:** A complete detection zone system with:
- `DetectionZone.swift` model with containment, size, and aspect filtering
- `CardPresenceTracker` integration with zone filtering and calibration
- `AutoScanViewModel` lifecycle management with calibration on capture
- `DetectionOverlayRenderer` visual zone boundary overlay (dashed blue line)
- Settings UI with "Reset Detection Zone" button
- 22 comprehensive unit tests covering all filtering logic

**Deferred items:** None

## Code Review Checklist

Evaluate each criterion against the changes made. State pass or fail with brief evidence.

### 1. Correctness

**Result:** pass

All three filtering criteria implemented correctly:
- `contains()` uses `effectiveRect` which expands by `tolerance` on all sides
- `isLargeEnough()` compares box area to `minAreaFraction` (0.40)
- `isPortraitAspect()` validates width/height ≤ 0.8 (portrait cards)

Edge cases handled:
- Zero-height boxes return false for aspect check
- Full-frame zone (0,0,1,1) with zero tolerance for default state
- Coordinate space: uses YOLO top-left origin consistently

### 2. Simplicity

**Result:** pass

- `DetectionZone.swift`: 78 lines total, all methods < 20 lines
- No unnecessary abstractions; methods do exactly one thing
- Nesting: max 2 levels in all methods (guard + return)

### 3. No Scope Creep

**Result:** pass

- Only implements detection zone filtering as specified
- No added features beyond the plan
- No dead code or commented-out code
- Settings reset uses existing Environment key pattern

### 4. Tests

**Result:** pass

- 22 `DetectionZoneTests` covering all filtering methods
- Tests for boundary conditions (exact threshold, just below, just above)
- Combined filter tests verify all three criteria together
- `DetectionOverlayRendererTests` updated for new zone overlay layer

### 5. Safety

**Result:** pass

- No force unwraps in production code
- `guard` statements for optional handling
- `effectiveRect` computed property is safe
- All types use explicit annotations

### 6. API Contract

**Result:** not applicable

No API changes; all work is iOS-only (Swift/SwiftUI).

### 7. Artifacts and Observability

**Result:** pass

- Zone overlay provides visual feedback during auto-scan
- `isCalibrated` state tracks calibration status
- Debug artifacts still produced by recognition pipeline

### 8. Static Analysis

**Result:** pass

- SwiftLint: 0 violations in 97 files
- Build: successful with no warnings
- No new suppressions added

## Verification Results

```
make ios-build: SUCCESS
make ios-test: TEST SUCCEEDED (22 DetectionZoneTests, 20 DetectionOverlayRendererTests, all pass)
make ios-lint: SwiftLint passed (0 violations, 0 serious in 97 files)
```

Full test suite: All tests pass.

## Notes

- Coordinate space discovery: YOLO uses top-left origin; Vision uses bottom-left. `DetectionZone` operates in YOLO top-left coordinates, matching what `CardPresenceTracker` produces. The overlay renderer converts to Vision coordinates for display.
- Tolerance behavior: `effectiveRect` expands the reference rect by `dx = width * tolerance`. A box must be fully inside the expanded rect to pass `contains()`.
- Test fixes: Two combined filter tests had incorrect test data. Fixed by correcting box dimensions to properly exercise the intended filter failure case.
