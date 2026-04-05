# Plan: Torch Settings, Card Title Toasts, Auto-Scan Stop

**Planned by:** Claude (kimi-k2.5)
**Date:** 2026-04-04

## Approach

I will implement three independent UI/UX improvements to the scan screen:

1. **Torch Persistence**: Add a `lastTorchLevel` property to `AppModel` (in-memory only, no UserDefaults). In `ScanView.onDisappear`, save the current torch level before turning it off. In `ScanView.onAppear`, restore it if > 0 and camera permission is granted.

2. **Card Title Toasts**: Create a new `IdentifiedCardToastView` that displays individual card notifications. Create `IdentifiedCardsViewModel` to manage the queue of recent cards (max 10) with auto-dismiss. Modify `RecognitionQueue` to emit card identification events via callback, wired through `QuickScanViewModel` to the toast view. Toasts slide in from the trailing edge with animation and fade out after 3 seconds.

3. **Auto-Scan Stop**: Ensure `QuickScanViewModel.stop()` is called in `ScanView.onDisappear`. Verify `stop()` sets `isActive = false` and `captureState = .watching`, preventing background processing.

All three features are independent and can be implemented in any order.

## Implementation Steps

### Feature 1: Torch Settings Persistence

1. **Modify `AppModel.swift`**
   - Add `@Published var lastTorchLevel: Float = 0` (in-memory, no persistence)
   
2. **Modify `ScanView.swift`**
   - In `onDisappear`: Save `detectionViewModel.torchLevel` to `appModel.lastTorchLevel` before setting to 0
   - In `onAppear`: After camera permission check, if `appModel.lastTorchLevel > 0`, restore it to `detectionViewModel.torchLevel`

### Feature 2: Card Title Toasts

3. **Create `IdentifiedCard.swift` (Model)**
   - Simple struct with: id (UUID), title (String), isFoil (Bool), setCode (String), collectorNumber (String), createdAt (Date)

4. **Create `IdentifiedCardsViewModel.swift`**
   - `@Published var recentCards: [IdentifiedCard] = []`
   - `maxCards = 10`, `displayDuration = 3.0` seconds
   - `addCard(_:)` method: insert at beginning, remove old if > max
   - Auto-remove cards after displayDuration using Timer or Task

5. **Create `IdentifiedCardToastView.swift`**
   - SwiftUI view for individual toast
   - Slide in from trailing edge using `.transition(.move(edge: .trailing))`
   - Display: title (prominent), foil indicator, set code, collector number
   - Semi-transparent background, rounded corners

6. **Modify `RecognitionQueue.swift`**
   - Add callback: `var onCardIdentified: ((RecognitionResult.Card) -> Void)?`
   - In `process(job:)`, after successful API call, call `onCardIdentified?` for each card in result

7. **Modify `QuickScanViewModel.swift`**
   - Add reference to `IdentifiedCardsViewModel` (or publish events)
   - Wire `recognitionQueue.onCardIdentified` to forward cards

8. **Modify `ScanView.swift`**
   - Add `@StateObject private var identifiedCardsViewModel = IdentifiedCardsViewModel()`
   - Add toast overlay in ZStack (above camera preview, below menu)
   - Pass view model to QuickScanViewModel

### Feature 3: Auto-Scan Stop

9. **Modify `ScanView.swift`**
   - In `onDisappear`: Add explicit call to `quickScanViewModel.stop()`
   
10. **Verify `QuickScanViewModel.stop()`** (already exists, confirm behavior)
    - Sets `isActive = false`
    - Sets `captureState = .watching`
    - Clears any pending state

11. **Add safety check in `QuickScanViewModel.processFrame()`**
    - Early return if `!isActive` to prevent processing after stop

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScanner/Models/AppModel.swift` | Add `lastTorchLevel` property (in-memory) |
| `apps/ios/MTGScanner/Features/Scan/ScanView.swift` | Restore/save torch; add stop() call; add toast overlay |
| `apps/ios/MTGScanner/Features/QuickScan/QuickScanViewModel.swift` | Wire card identification events; add isActive guard |
| `apps/ios/MTGScanner/Features/QuickScan/RecognitionQueue.swift` | Add `onCardIdentified` callback |
| `apps/ios/MTGScanner/Features/Scan/ViewModels/IdentifiedCardsViewModel.swift` | **NEW** Manage recent cards queue with auto-dismiss |
| `apps/ios/MTGScanner/Features/Scan/Views/IdentifiedCardToastView.swift` | **NEW** Individual toast view component |
| `apps/ios/MTGScanner/Features/Scan/Models/IdentifiedCard.swift` | **NEW** Data model for identified card toast |

## Risks and Open Questions

- **Toast Animation**: SwiftUI `.transition(.move(edge: .trailing))` should work well, but need to verify layout with safe areas on different devices
- **Recognition Result Mapping**: Need to verify `RecognitionResult.Card` has all required fields (title, isFoil, setCode, collectorNumber) - if not, may need to map from `CollectionItem` or similar
- **Thread Safety**: `RecognitionQueue` processes on background thread, callback must dispatch to main thread for UI updates. Will verify `onCardIdentified` is called from main actor or use `Task { @MainActor in }`
- **Memory**: Keeping 10 cards in memory is trivial, no risk

## Verification Plan

1. **Baseline Verification** (before changes):
   ```bash
   xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build
   ```

2. **Torch Verification**:
   - Manual: Turn on torch at 50%, navigate to Library and back
   - Expected: Torch restored to 50%
   - Manual: Kill app, reopen scan view
   - Expected: Torch is off (0)

3. **Card Titles Verification**:
   - Enable quick scan, scan cards (or use mock recognition)
   - Observe toasts sliding in from trailing edge
   - Verify card details displayed correctly
   - Verify max 10 cards, older ones removed
   - Verify toasts auto-dismiss after ~3 seconds

4. **Auto-Scan Stop Verification**:
   - Start quick scan
   - Navigate away
   - Return to scan view
   - Verify scanning is stopped (status shows "Tap Start to begin" or similar)
   - Verify no background processing (CPU should be idle)

5. **Build Verification**:
   ```bash
   xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build
   ```

6. **Code Review Checklist**:
   - Run against `.claude/rules/code-review.md` criteria
   - Each criterion: pass/fail with evidence
