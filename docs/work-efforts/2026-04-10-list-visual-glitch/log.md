# Log: Collections list rounding glitch

- 2026-04-10: Worktree created for feature work.
- 2026-04-10: Request/plan/review scaffolding created under `docs/work-efforts/2026-04-10-list-visual-glitch/`.
- 2026-04-10: Baseline verification completed. `make ios-build` passed. `make ios-lint` failed with pre-existing SwiftLint violations in `RectangleFilter.swift`, `RecognitionQueueTests.swift`, `RectangleFilterTests.swift`, and `ScanYOLOSupportTests.swift`.
- 2026-04-10: Investigated the Collections list implementation in `LibraryView.swift` and compared it to `CollectionDetailView.swift` and `DeckDetailView.swift`. No custom row clipping, masking, corner radius, or first/last-row-specific backgrounds were present in the Library rows.
- 2026-04-10: Found the main implementation difference from the detail lists was delete handling. Library rows used section-level `.onDelete`, while the detail lists attach explicit row-level `.swipeActions(edge: .trailing, allowsFullSwipe: true)`.
- 2026-04-10: Applied a narrowly scoped fix by moving Library collection and deck deletion to explicit row-level swipe actions, preserving the existing context menus and navigation while aligning the swipe container behavior with the detail lists that already animate correctly.
- 2026-04-10: Post-change verification completed. `make ios-build` still passed, `make ios-lint` still failed with the same pre-existing SwiftLint violations outside this task, and targeted linting passed for `LibraryView.swift`.
