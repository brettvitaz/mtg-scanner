# Log: Collections list rounding glitch

- 2026-04-10: Worktree created for feature work.
- 2026-04-10: Request/plan/review scaffolding created under `docs/work-efforts/2026-04-10-list-visual-glitch/`.
- 2026-04-10: Baseline verification completed. `make ios-build` passed. `make ios-lint` failed with pre-existing SwiftLint violations in `RectangleFilter.swift`, `RecognitionQueueTests.swift`, `RectangleFilterTests.swift`, and `ScanYOLOSupportTests.swift`.
- 2026-04-10: Investigated the Collections list implementation in `LibraryView.swift` and found it relied on automatic `List` styling, while comparable card lists already pin `.listStyle(.insetGrouped)`.
- 2026-04-10: Applied a narrowly scoped fix by explicitly using `.listStyle(.insetGrouped)` for the Library list so the Collections section uses stable inset-grouped row treatment during swipe and long-press interactions.
- 2026-04-10: Post-change verification completed. `make ios-build` still passed, `make ios-lint` still failed only with the same pre-existing violations, targeted linting passed for `LibraryView.swift`, and the built app was installed/launched in the iPhone 16 Pro simulator.
