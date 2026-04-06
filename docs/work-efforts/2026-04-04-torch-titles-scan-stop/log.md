# Log: Torch Settings, Card Title Toasts, Auto-Scan Stop

## Progress

### Step 1: Baseline Verification

**Status:** done

Ran baseline build to establish pre-implementation state:
```bash
xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build
```
Result: BUILD SUCCEEDED (with existing warnings about duplicate files and deprecated APIs)

Deviations from plan: none

---

### Step 2: Feature 1 - Torch Settings Persistence

**Status:** done

Added `lastTorchLevel` property to AppModel (in-memory only, no UserDefaults persistence as requested).
Modified ScanView.onAppear to restore torch level and onDisappear to save it before turning off.

Files modified:
- `apps/ios/MTGScanner/App/AppModel.swift` - Added `@Published var lastTorchLevel: Float = 0`
- `apps/ios/MTGScanner/Features/Scan/ScanView.swift` - Added save/restore logic and `restoreTorchLevel()` helper

Deviations from plan: none

---

### Step 3: Feature 2 - Card Title Toast Notifications

**Status:** done

Created toast notification system with:
- `IdentifiedCard` model (added to RecognitionModels.swift) - stores card data for toasts
- `IdentifiedCardsViewModel` (added to QuickScanViewModel.swift) - manages queue of recent cards with auto-dismiss
- `IdentifiedCardToastView` and `IdentifiedCardToastContainer` (added to ScanView.swift) - UI components with slide-in animation from trailing edge

Modified RecognitionQueue to emit card identification events via `onCardIdentified` callback.
Wired callback through QuickScanViewModel to IdentifiedCardsViewModel.
Added toast container overlay to ScanView cameraOverlay.

Files modified:
- `apps/ios/MTGScanner/Models/RecognitionModels.swift` - Added IdentifiedCard struct
- `apps/ios/MTGScanner/Features/QuickScan/QuickScanViewModel.swift` - Added IdentifiedCardsViewModel class and wired callback
- `apps/ios/MTGScanner/Features/QuickScan/RecognitionQueue.swift` - Added onCardIdentified callback
- `apps/ios/MTGScanner/Features/Scan/ScanView.swift` - Added toast views and container to overlay

Deviations from plan:
- Originally planned to create separate files in new directories (Models/, ViewModels/, Views/)
- Changed to integrate code into existing files to avoid complex Xcode project file modifications
- All functionality identical, just organized differently

---

### Step 4: Feature 3 - Auto-Scan Stop

**Status:** done

Modified ScanView.onDisappear to call `quickScanViewModel.stop()` to ensure auto-scan mode stops when leaving scan view.
Verified QuickScanViewModel.stop() properly sets isActive=false, cancels settleTask, sets captureState to .watching, and clears identified cards.
Added isActive guard in processFrame() (already existed).
Modified stop() to also clear identified cards toasts.

Files modified:
- `apps/ios/MTGScanner/Features/Scan/ScanView.swift` - Added quickScanViewModel.stop() call in onDisappear
- `apps/ios/MTGScanner/Features/QuickScan/QuickScanViewModel.swift` - Added clearAll() call in stop()

Deviations from plan: none

---

### Step 5: Build Verification

**Status:** done

Final build check:
```bash
xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build
```
Result: BUILD SUCCEEDED

Warnings (pre-existing):
- Duplicate build file: CardDetailSubviews.swift
- Deprecated API: onChange(of:perform:) in SettingsView.swift
- Non-Sendable capture warnings in CardPresenceTracker.swift

Deviations from plan: none

---

### Step 6: Code Review and Fixes

**Status:** done

Dispatched code-reviewer subagent for review. Assessment: "Ready for production with minor cleanups."

**Issues found and fixed:**
1. **Redundant Task wrapper** (QuickScanViewModel.swift:94-100)
   - Original: Nested `Task { @MainActor [weak self] in }` inside callback
   - Issue: Already on MainActor from RecognitionQueue.persist()
   - Fix: Removed redundant Task wrapper, direct assignment now
   - Build still succeeds after fix

**Issues noted (minor, not fixed):**
- `removeCard` could be private (style preference)
- Missing tests for toast functionality (UI-focused feature, manual testing recommended)

Deviations from plan: Applied code review feedback to simplify callback

---

### Step 7: Post-Review Fixes (External Review)

**Status:** done

Received external code review findings on toast implementation. Addressed all issues:

**Critical fix - Foil shimmer hit testing:**
- Issue: Shimmer overlay at line 303 blocked taps on dismiss button
- Fix: Added `.allowsHitTesting(false)` to shimmer overlay Group (line 331)

**Important fix - Layout compression:**
- Issue: Single-row HStack could truncate set code and collector number on narrow widths
- Fix: Added `.layoutPriority(1)` to set code (line 274) and collector number (line 281)

**Important fix - Accessibility:**
- Issue: Dismiss button 24×24 below Apple's 44×44 minimum, missing accessibility label
- Fix: Changed to `minWidth: 44, minHeight: 44` with `contentShape`, added `.accessibilityLabel("Dismiss")` (lines 290-298)

**Minor fix - Reduce Motion:**
- Issue: Shimmer animation ignored Reduce Motion preference
- Fix: Added `@Environment(\.accessibilityReduceMotion)` and gated animation (lines 256, 333)

Files modified:
- `apps/ios/MTGScanner/Features/Scan/ScanView.swift` - All four fixes applied

Build verification:
```bash
xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build
```
Result: BUILD SUCCEEDED

Deviations from plan: None - all fixes applied as specified in review

---
