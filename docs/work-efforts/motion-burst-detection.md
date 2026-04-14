# Motion Burst Detection Enhancement

## Problem Statement

Shadows from overhead lighting in the fixture-mounted iPhone setup cause false positive capture events. The current detection uses a single-frame luminance threshold (0.03) which is easily crossed by:
- Hand shadows passing over the scanning area
- Ambient light changes from overhead fixtures
- Sustained shadows that persist for 0.5s to multiple seconds

## Solution: Motion Burst Detection

Replace the single-frame threshold with a temporal pattern detector that looks for the characteristic signature of a card sliding into the bin:

1. **Burst Phase**: Rapid sequence of frame changes as card enters frame
2. **Settlement Phase**: Consecutive frames with minimal change (card at rest)

Shadows produce different patterns:
- Transient shadows: single step change, no settlement
- Sustained shadows: elevated baseline but no burst pattern

## Implementation Components

### 1. MotionBurstDetector (New Class)

Encapsulates burst/settlement detection logic:
- Ring buffer for recent diff values
- State machine: `idle` → `burstDetected` → `settled` (capture) or `hovering` → reset
- Configurable burst/settlement parameters

```swift
enum BurstDetectionState {
    case idle
    case burstDetected(burstStartFrame: Int)
    case hovering(burstStartFrame: Int)
    case settled
}

struct MotionBurstConfiguration {
    var burstFrameCount: Int      // Frames required above threshold (default: 4)
    var burstWindowSize: Int      // Total frames in evaluation window (default: 6)
    var settlementFrames: Int     // Consecutive low frames to confirm settlement (default: 3)
    var motionThreshold: Float    // Frame difference threshold (default: 0.03)
    var maxHoverDuration: Int     // Max frames in burst without settlement (default: 10)
}
```

### 2. Reference Frame Decay (Option D)

After 5 seconds without a trigger, update the reference frame to the current frame. This prevents sustained shadows from permanently elevating the baseline.

```swift
private let referenceDecayTimeout: TimeInterval = 5.0
```

### 3. Configuration Settings

New settings section "Auto Scan Sensitivity" with persisted values:

| Setting | Description | Default | Range |
|---------|-------------|---------|-------|
| Burst Frame Count | Frames above threshold to detect burst | 4 | 2-8 |
| Burst Window Size | Total frames in evaluation window | 6 | 4-12 |
| Settlement Frames | Consecutive low frames for settlement | 3 | 2-6 |
| Motion Threshold | Frame difference threshold | 0.03 | 0.01-0.10 |
| Reference Decay Timeout | Seconds before reference auto-updates | 5.0 | 2-10 |
| Max Hover Duration | Max frames in burst without settlement | 10 | 5-20 |

Preserved via `@AppStorage` with reset-to-default button.

### 4. Debug Overlay (Optional)

When enabled in settings, overlay shows:
- Current burst detection state (idle/bursting/hovering/settled)
- Recent diff sparkline graph
- Frame counter since last state change
- Rejection reason logging

### 5. Hovering State Handling

When sustained burst is detected (motion continues beyond expected settlement):
- Lock reference frame (keep using pre-burst reference)
- Continue monitoring for settlement
- If settlement occurs → proceed with capture
- If motion stops without settlement (hand removed) → update reference, return to idle

## Configuration Presets

Three built-in presets for quick tuning:

| Preset | Burst | Window | Settlement | Threshold | Use Case |
|--------|-------|--------|------------|-----------|----------|
| Fast | 3 | 5 | 2 | 0.04 | Aggressive, quick scanning |
| Balanced | 4 | 6 | 3 | 0.03 | Default, works for most fixtures |
| Conservative | 6 | 10 | 5 | 0.02 | Strict, rejects more shadows |

## State Machine Flow

```
[idle] --(burst detected)--> [burstDetected]
    ↑                              |
    |                              | (settlement detected)
    |                              ↓
[hover timeout] <---------- [settled] --> trigger capture
    ↑                              |
    |________(hover continues)_____|
```

## Testing Strategy

1. **Unit Tests**: `MotionBurstDetectorTests`
   - Burst detection with various frame sequences
   - Settlement confirmation logic
   - Hover timeout behavior
   - State transitions

2. **Integration Tests**: Update `CardPresenceTrackerTests`
   - Verify integration with YOLO detector
   - Reference frame decay behavior
   - Configuration injection

3. **Manual Testing**: Debug overlay metrics
   - Log burst detection events
   - Log settlement times
   - Log rejection reasons
   - Tune for specific fixture lighting

## Files to Modify

### New Files
- `MotionBurstDetector.swift` - Core burst detection logic
- `MotionBurstConfiguration.swift` - Configuration struct and presets
- `BurstDetectionState.swift` - State enum
- `MotionBurstDetectorTests.swift` - Unit tests

### Modified Files
- `CardPresenceTracker.swift` - Integrate MotionBurstDetector
- `AutoScanViewModel.swift` - Inject configuration, handle settings
- `SettingsView.swift` - Add new settings section
- `AutoScanSettings.swift` - New settings model (if not existing)

## Migration Path

1. Implement `MotionBurstDetector` with tests
2. Update `CardPresenceTracker` to use burst detection (feature flag for fallback)
3. Add settings UI
4. Add debug overlay
5. Remove feature flag, make burst detection default
6. Remove legacy single-threshold code path

## References

- Original coordinate fix worktree: `improve-autoscan-accuracy`
- Current detection: `FrameDifferenceAnalyzer` with `sceneChangeThreshold = 0.03`
- YOLO integration: `CardPresenceTracker.process(pixelBuffer:)`

## Success Criteria

- [x] Core motion burst detection implemented
- [x] Reference frame decay implemented
- [x] All tests pass (361 tests)
- [x] SwiftLint passes (0 violations)
- [ ] Settings UI with persistence
- [ ] Debug overlay
- [ ] Manual testing in fixture

## Implementation Status

### Completed

**Phase 1: Core Components**
- `BurstDetectionState.swift` - State enum with display names and active status
- `MotionBurstConfiguration.swift` - Configuration struct with presets (balanced/fast/conservative)
- `MotionBurstDetector.swift` - Core burst detection with ring buffer and state machine

**Phase 2: Integration**
- Updated `CardPresenceTracker.swift` to use `MotionBurstDetector`
- Added `burstConfiguration` property with didSet observer
- Added `useLegacyDetection` flag for fallback
- Added `onDebugMetrics` callback for overlay support
- Added `setDebugMode()` method
- Implemented reference decay in `markCaptured()` and `process()`
- Refactored `process(pixelBuffer:)` into smaller functions (lint compliance)

**Phase 3: Testing**
- `MotionBurstDetectorTests.swift` - State machine and core functionality (14 tests)
- `MotionBurstDecayTests.swift` - Reference decay behavior (3 tests)
- `MotionBurstConfigurationTests.swift` - Presets and validation (5 tests)

### Remaining

**Phase 4: Settings UI**
- Add settings model with `@AppStorage` persistence
- Create settings view section "Auto Scan Sensitivity"
- Implement reset-to-default button
- Add preset selection (Fast/Balanced/Conservative)

**Phase 5: Debug Overlay**
- Create debug overlay view
- Display burst detection state
- Show diff sparkline graph
- Show frame counters and rejection reasons

**Phase 6: Validation**
- Test in fixture with real cards
- Tune default values based on results
- Verify shadow rejection improvement

## Files Created/Modified

### New Files
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/BurstDetectionState.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/MotionBurstConfiguration.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/MotionBurstDetector.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/MotionBurstDetectorTests.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/MotionBurstDecayTests.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/MotionBurstConfigurationTests.swift`

### Modified Files
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/CardPresenceTracker.swift`

## Verification Results

```bash
$ make ios-build
** BUILD SUCCEEDED **

$ make ios-test
361 tests passed, 0 failed

$ make ios-lint
Done linting! Found 0 violations, 0 serious in 103 files.
SwiftLint passed.
```
