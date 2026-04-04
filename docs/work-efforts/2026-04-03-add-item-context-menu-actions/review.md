# Review: Add Item Context Menu Actions

**Reviewed by:** Codex
**Date:** 2026-04-03

## Summary

**What was requested:** Add native long-press row actions for items in Results, Collection Detail, and Deck Detail, preserving copy flows, navigation, foil-toggle safety, and delete undo behavior.

**What was delivered:** Shared `contextMenu` row actions for copy, delete, and foil toggle shipped across the three item-list screens, with foil-collision protection, centralized latest-delete shake undo, and focused XCTest coverage for the foil-toggle and undo logic.

**Deferred items:** Manual UI acceptance checks were documented but not executed in this terminal-only session. A pre-existing duplicate compile-source warning for `CardDetailSubviews.swift` remains in the project file because it is unrelated to this request.

## Code Review Checklist

Evaluate each criterion against the changes made. State pass or fail with brief evidence.

### 1. Correctness

**Result:** pass

The three target screens now expose the requested native long-press actions, copy still uses the existing move sheet flow, delete registers undo, and foil toggles are blocked when they would collide with an existing sibling item. The review-found undo bug was resolved by centralizing the latest undo action in `AppModel`.

### 2. Simplicity

**Result:** pass

The change uses a small shared row-action pattern and a simple centralized undo slot rather than adding view models or complex coordination. Logic remains local to each screen where parent-specific timestamp updates differ, and control flow stays shallow.

### 3. No Scope Creep

**Result:** pass

The work stayed within Results, Collection Detail, Deck Detail, shared row behavior, foil-toggle safety, and delete undo. Unrelated project warnings and broader backend lint/test issues were not changed.

### 4. Tests

**Result:** pass

`CollectionItemFoilToggleTests` covers allowed and blocked foil toggles across inbox, collection, and deck scenarios. `AppModelUndoTests` covers latest-action overwrite and one-time undo clearing, which would fail if the centralized undo implementation were broken.

### 5. Safety

**Result:** pass

The Swift changes do not introduce force unwraps or unsafe thread usage. Undo coordination is safer than the prior review-found approach because it eliminates cross-screen notification fanout and restores only the latest delete.

### 6. API Contract

**Result:** not applicable

This is an iOS-only UI and model-behavior change. No backend endpoints, schemas, or mock contracts were modified.

### 7. Artifacts and Observability

**Result:** not applicable

The change does not affect recognition artifacts or backend observability. User-visible conflict alerts and existing haptic feedback remain the primary feedback mechanisms for these item actions.

### 8. Static Analysis

**Result:** pass

`make ios-lint` passed after the final changes. No new suppressions were added.

## Verification Results

- `make ios-lint`: passed with 0 violations.
- `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`: passed.
- `xcodebuild test -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -destination 'platform=iOS Simulator,OS=18.6,name=iPhone 16' -only-testing:MTGScannerTests/CollectionModelsTests -only-testing:MTGScannerTests/CollectionItemFoilToggleTests -only-testing:MTGScannerTests/AppModelUndoTests`: passed.
- Test coverage exercised `CollectionModelsTests`, `CollectionItemFoilToggleTests`, and `AppModelUndoTests`.
- Build output still included a pre-existing warning about a duplicate compile source entry for `CardDetailSubviews.swift`.

## Notes

The implementation landed in two commits in this worktree: the feature commit `1955a3c` and the review follow-up commit `25785ac`. The worktree is clean after the documentation update and remains the correct location for any follow-up UI validation.
