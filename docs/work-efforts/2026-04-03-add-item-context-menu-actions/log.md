# Log: Add Item Context Menu Actions

## Progress

Append a new step section each time you complete a meaningful unit of work.
Use the format below. Do not use tables — headings and paragraphs are easier to maintain.

### Step 1: Implemented shared row context-menu actions

**Status:** done

Added shared long-press actions for item rows and wired them into Results, Collection Detail, and Deck Detail. Replaced the old per-item long-press delete dialog flow with `Copy`, `Delete`, and `Toggle Is Foil` actions while keeping tap navigation and multi-select behavior intact.

Deviations from plan: none

---

### Step 2: Added foil-toggle collision handling and tests

**Status:** done

Added model logic to block foil toggles that would create a duplicate sibling item in the same inbox, collection, or deck, and surfaced an alert in the affected screens when the toggle is rejected. Added focused XCTest coverage for the foil-toggle helper and updated the Xcode project to include the new test file.

Deviations from plan: none

---

### Step 3: Ran initial verification and recorded environment limits

**Status:** done

Ran `make ios-lint`, `xcodebuild ... build`, and targeted iOS tests for the new foil-toggle logic. Earlier repo-wide backend baseline commands remained constrained by pre-existing environment issues: `make api-test` was blocked by artifact-directory write permissions in sandboxed execution and `make api-lint` / `make lint` hit a `mypy` segmentation fault.

Deviations from plan: limited verification to the Swift scope because the broader backend/static-analysis failures were unrelated to this iOS change.

---

### Step 4: Addressed review finding on global shake undo behavior

**Status:** done

After review flagged that a global shake notification could restore deletions from multiple mounted screens, centralized the latest undo action in `AppModel` and changed the root shake detector to invoke that single latest undo directly. Removed the old notification-based undo listeners from Results, Collection Detail, Deck Detail, and `ShakeDetector`.

Deviations from plan: expanded the undo implementation beyond the initial per-screen approach because the review found a correctness bug.

---

### Step 5: Added undo regression tests and re-verified the patch

**Status:** done

Added `AppModelUndoTests` to verify only the latest registered delete is undone and that the undo action is cleared after use. Re-ran `make ios-lint`, `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`, and targeted `xcodebuild test` for `CollectionModelsTests`, `CollectionItemFoilToggleTests`, and `AppModelUndoTests`; all passed.

Deviations from plan: none
