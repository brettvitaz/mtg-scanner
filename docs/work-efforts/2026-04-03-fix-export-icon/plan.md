# Plan: Fix export icon

**Planned by:** opencode
**Date:** 2026-04-03

## Approach

Replace the `ellipsis.circle` SF Symbol used as the export menu button icon with `square.and.arrow.up` (the standard Apple share icon) across all three detail views. This is a simple find-and-replace of the SF Symbol name in the label closures of existing `Menu` components.

## Implementation Steps

1. Update `ResultsView.swift` — Replace `Image(systemName: "ellipsis.circle")` with `Image(systemName: "square.and.arrow.up")` in both selection mode and normal mode export menus (2 occurrences at lines 136, 145).
2. Update `CollectionDetailView.swift` — Same replacement in both selection mode and normal mode export menus (2 occurrences at lines 125, 134).
3. Update `DeckDetailView.swift` — Same replacement in both selection mode and normal mode export menus (2 occurrences at lines 131, 140).
4. Run `make ios-lint` to verify SwiftLint passes.
5. Build the iOS project to confirm no compilation errors.

All steps are independent and could run in parallel, but will be done sequentially for safety.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScanner/Features/Results/ResultsView.swift` | Replace `"ellipsis.circle"` with `"square.and.arrow.up"` (2 occurrences) |
| `apps/ios/MTGScanner/Features/Library/CollectionDetailView.swift` | Replace `"ellipsis.circle"` with `"square.and.arrow.up"` (2 occurrences) |
| `apps/ios/MTGScanner/Features/Library/DeckDetailView.swift` | Replace `"ellipsis.circle"` with `"square.and.arrow.up"` (2 occurrences) |

## Risks and Open Questions

- None. This is a cosmetic-only change to SF Symbol names. The `square.and.arrow.up` symbol is a standard Apple SF Symbol available on iOS 17+.
- The export menu items inside already use `square.and.arrow.up`, so this makes the button icon consistent with its contents.

## Verification Plan

1. Run `make ios-lint` — SwiftLint should pass with no new warnings.
2. Run `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build` — Build should succeed.
3. Manual verification: The export button in Results, Collection Detail, and Deck Detail views should display the Apple share icon instead of `...`.
