# Log: Library list visual glitch

- 2026-04-10: Worktree created for feature work.
- 2026-04-10: Request/plan/review scaffolding created under `docs/work-efforts/2026-04-10-list-visual-glitch/`.
- 2026-04-10: Baseline verification completed. `make ios-build` passed. `make ios-lint` failed with pre-existing SwiftLint violations outside this task.
- 2026-04-10: Investigated `LibraryView.swift` and compared it with `CollectionDetailView.swift` and `DeckDetailView.swift`.
- 2026-04-10: Confirmed a key architectural difference: top-level Library used section-level delete behavior while the detail lists used explicit row-level swipe actions.
- 2026-04-10: Explored several diagnostic changes in `LibraryView`, including row backgrounds, custom section headers, matching the detail-view container structure, and forcing `.plain` list styling.
- 2026-04-10: Added loud debug visuals and physical-device version bumps to prove which list surfaces were actually being rendered. This helped show that the visible affected list was in the detail-view path, not just the top-level Library landing screen.
- 2026-04-10: Confirmed on device that the detail-view list path was part of the real issue, then removed the debug-only visuals and version-bump noise from the final patch.
- 2026-04-10: Final Library/detail-view fix set kept the affected Library list surfaces on `.plain` list styling and used explicit header views with a system-background treatment, while preserving rename/create behavior.
- 2026-04-10: Temporarily changed `ResultsView.swift` while investigating the scanned-card count behavior, but Brett decided the sticky scanned-card count was preferred. The final patch keeps that sticky Results behavior.
- 2026-04-10: Final on-device verification used explicit `devicectl` install and launch, not `xcodebuild install`, to ensure the tested build actually reached Brett’s phone.
