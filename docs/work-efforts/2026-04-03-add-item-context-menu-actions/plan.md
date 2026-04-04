# Plan: Add Item Context Menu Actions

**Planned by:** Codex
**Date:** 2026-04-03

## Approach

Replace the per-screen long-press delete handling with a shared row action pattern built around `contextMenu`, while preserving the current navigation and copy flows. Keep most screen-specific logic local by passing closures for copy, delete, and foil-toggle into the shared row helper. Add a foil-collision helper in the model layer so the UI can block invalid toggles consistently, and verify undo behavior with focused tests after centralizing the latest delete undo action.

## Implementation Steps

1. Update the shared item row UI to support optional context-menu actions and wire that into Results, Collection Detail, and Deck Detail when not in multi-select mode.
2. Remove the old single-item long-press delete dialog state from the three screens and route copy, delete, and foil-toggle through screen-specific handlers.
3. Add a foil-toggle collision helper in `CollectionModels.swift` so toggling is blocked when it would duplicate an item in the same parent list.
4. Preserve delete undo by registering the latest undo action centrally in `AppModel` and invoking it from the root shake detector.
5. Add XCTest coverage for foil-toggle collisions and the centralized latest-delete undo behavior, then run lint, build, and targeted tests.

Step 2 depends on step 1 because the screens need the shared row action API. Step 4 depends on the delete handlers in step 2. Step 5 depends on the model and undo changes from steps 3 and 4.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScanner/Features/Shared/CollectionItemRow.swift` | Add shared context-menu support for row-level actions. |
| `apps/ios/MTGScanner/Features/Results/ResultsView.swift` | Replace per-item long-press dialog state with copy/delete/foil handlers and latest-undo registration. |
| `apps/ios/MTGScanner/Features/Library/CollectionDetailView.swift` | Same row action behavior for collection items, including collection timestamp updates. |
| `apps/ios/MTGScanner/Features/Library/DeckDetailView.swift` | Same row action behavior for deck items, including deck timestamp updates. |
| `apps/ios/MTGScanner/Models/CollectionModels.swift` | Add foil-toggle collision detection helper. |
| `apps/ios/MTGScanner/App/AppModel.swift` | Store and run the latest delete undo action. |
| `apps/ios/MTGScanner/App/RootTabView.swift` | Route shake detection into centralized undo handling. |
| `apps/ios/MTGScanner/Features/Shared/ShakeDetector.swift` | Keep shake detection focused on callback delivery, not notifications. |
| `apps/ios/MTGScannerTests/CollectionItemFoilToggleTests.swift` | Add foil-toggle collision tests. |
| `apps/ios/MTGScannerTests/AppModelUndoTests.swift` | Add regression tests for centralized undo behavior. |
| `apps/ios/MTGScanner.xcodeproj/project.pbxproj` | Register new test source files. |

## Risks and Open Questions

- Assume "press and hold" means native iOS `contextMenu`, not immediate destructive action.
- The existing shake-to-undo path spans multiple screens, so centralizing the latest undo action is safer than broadcasting a global notification.
- A pre-existing duplicate compile-source warning for `CardDetailSubviews.swift` may appear during builds but is outside this task's scope.

## Verification Plan

- Run `make ios-lint`.
- Run `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`.
- Run `xcodebuild test -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -destination 'platform=iOS Simulator,OS=18.6,name=iPhone 16' -only-testing:MTGScannerTests/CollectionModelsTests -only-testing:MTGScannerTests/CollectionItemFoilToggleTests -only-testing:MTGScannerTests/AppModelUndoTests`.
- Manually verify long-press menus, tap navigation, select mode, delete undo, and foil-toggle conflict alerts on the three screens.
