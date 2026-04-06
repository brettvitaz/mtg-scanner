# Request: Torch Settings, Card Title Toasts, Auto-Scan Stop

**Date:** 2026-04-04
**Author:** Brett

## Goal

Enhance the iOS scan screen with three UX improvements: persist and restore torch/flashlight settings during the app session, display animated toast notifications showing identified card details, and ensure auto-scan mode stops when leaving the scan view.

## Requirements

1. **Torch Settings Persistence**
   - Store torch level when leaving scan view
   - Restore torch level when returning to scan view (same app session only)
   - Do NOT persist across app restarts

2. **Card Title Toasts**
   - Show individual toast notifications as cards are identified
   - Toasts slide in from the side (left or right)
   - Display last 5-10 cards
   - Each toast shows: card title, isFoil flag, set code, collector number
   - Toasts auto-dismiss after a few seconds

3. **Auto-Scan Stop**
   - When leaving scan view, auto-scan mode must stop completely
   - No background processing should continue

## Scope

**In scope:**
- iOS scan view (ScanView.swift and related ViewModels)
- Card identification result handling (RecognitionQueue, QuickScanViewModel)
- Toast notification UI component
- Torch state management

**Out of scope:**
- Backend API changes
- Recognition accuracy improvements
- New detection modes
- Persistence across app restarts (for torch)

## Verification

1. **Torch:**
   - Turn on torch in scan view
   - Navigate away and return
   - Torch should be restored to previous level
   - Kill app and reopen - torch should be off (not persisted)

2. **Card Titles:**
   - Enable quick scan mode
   - Scan cards
   - Observe toast notifications sliding in from side
   - Verify card details (title, foil, set, collector number) display correctly
   - Verify max 5-10 cards shown, older ones dismissed

3. **Auto-Scan Stop:**
   - Start quick scan mode
   - Navigate away from scan view
   - Return - scanning should not automatically resume (user must tap Start)

4. **Build:**
   - `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build` passes

## Context

Files or docs the agent should read before starting:

- `apps/ios/MTGScanner/Features/Scan/ScanView.swift` - Main scan screen
- `apps/ios/MTGScanner/Features/CardDetection/ViewModels/CardDetectionViewModel.swift` - Torch state
- `apps/ios/MTGScanner/Features/QuickScan/QuickScanViewModel.swift` - Auto-scan logic
- `apps/ios/MTGScanner/Features/QuickScan/RecognitionQueue.swift` - Card identification results
- `apps/ios/MTGScanner/Models/AppModel.swift` - Session state management pattern
- `.claude/rules/code-review.md` - Code review criteria

## Notes

- Torch should restore only within same app session (in-memory storage, not UserDefaults)
- Toast design: individual cards sliding in from the side, not a list
- Keep toast UI simple - card title prominent, foil/set/collector as secondary info
