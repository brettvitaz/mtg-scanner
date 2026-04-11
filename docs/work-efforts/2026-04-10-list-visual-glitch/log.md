# Log: Collections list rounding glitch

- 2026-04-10: Worktree created for feature work.
- 2026-04-10: Request/plan/review scaffolding created under `docs/work-efforts/2026-04-10-list-visual-glitch/`.
- 2026-04-10: Baseline verification completed. `make ios-build` passed. `make ios-lint` failed with pre-existing SwiftLint violations in `RectangleFilter.swift`, `RecognitionQueueTests.swift`, `RectangleFilterTests.swift`, and `ScanYOLOSupportTests.swift`.
- 2026-04-10: Investigated the Collections list implementation in `LibraryView.swift` and compared it to `CollectionDetailView.swift` and `DeckDetailView.swift`. No custom row clipping, masking, corner radius, or first/last-row-specific backgrounds were present in the Library rows.
- 2026-04-10: Found the main implementation difference from the detail lists was delete handling. Library rows used section-level `.onDelete`, while the detail lists attach explicit row-level `.swipeActions(edge: .trailing, allowsFullSwipe: true)`.
- 2026-04-10: Applied a narrowly scoped fix by moving Library collection and deck deletion to explicit row-level swipe actions, preserving the existing context menus and navigation while aligning the swipe container behavior with the detail lists that already animate correctly.
- 2026-04-10: Post-change verification completed. `make ios-build` still passed, `make ios-lint` still failed with the same pre-existing SwiftLint violations outside this task, and targeted linting passed for `LibraryView.swift`.
- 2026-04-10: Applied explicit `.listRowBackground(Color(.systemBackground))` to both collection and deck rows in `LibraryView.swift`. Build passed, SwiftLint passed for the modified file. Manual simulator verification is needed to confirm the visual glitch is resolved.
- 2026-04-10: Reverted `listRowBackground` change. Moved `.contextMenu` from `NavigationLink` to inside `CollectionRow` view to match structure of working detail views. Build passed.
- 2026-04-10: Changed Section headers from string-based (`Section("Collections")`) to custom header views (`Section { ... } header: { HStack { ... } }`) to match working detail views. Build passed.
- 2026-04-10: Wrapped List in a `VStack(spacing: 0)` to match the structure of working detail views. Build passed.
- 2026-04-10: **TEMPORARY TESTING CHANGE**: Removed all `.contextMenu` functionality from LibraryView to test if context menu was conflicting with swipe actions and corner radius animations. Build passed. This is for diagnostic purposes only - rename functionality is temporarily unavailable.
- 2026-04-10: Added `.environment(\.editMode, .constant(.inactive))` to match the working detail views. Build passed.
- 2026-04-10: **DIAGNOSTIC TEST**: Changed `.listStyle(.insetGrouped)` to `.listStyle(.plain)` to test if the issue is specific to insetGrouped style. Build passed.
- 2026-04-10: Reverted to `.insetGrouped`. Added explicit `.listRowBackground(RoundedRectangle(cornerRadius: 0).fill(Color(.systemBackground)))` to force all corners to be square (matching Mail app behavior where all rows look the same). Build passed.
