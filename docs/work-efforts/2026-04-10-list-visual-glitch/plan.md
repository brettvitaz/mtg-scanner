# Plan: Library list visual glitch

**Planned by:** Ori
**Date:** 2026-04-10

## Approach

Treat this as a small focused iOS UI bugfix. Trace the actual Library list surfaces being rendered, compare them with the working behavior, and keep only the smallest changes that remove the unwanted rounded-row treatment while preserving normal interactions.

## Implementation Steps

1. Read the local execution and review rules (`CLAUDE.md`, `docs/feature-workflow.md`, `.claude/rules/code-review.md`) and inspect the relevant Library and Results UI files.
2. Establish a baseline:
   - `make ios-build`
   - `make ios-lint`
3. Identify which visible list surfaces are actually affected, including top-level Library and detail views.
4. Align the affected Library lists around the minimal structure/modifiers that remove the unwanted rounded-row behavior.
5. Re-run verification:
   - `make ios-build`
   - targeted on-device/manual validation
6. Complete code review against `.claude/rules/code-review.md`, recording pass/fail per criterion.
7. Update the work-effort docs with the final findings and decisions.
8. Commit the change with a meaningful message describing what changed and why.

## Files to Modify

Likely files only, to be confirmed during investigation:

- `apps/ios/.../LibraryView.swift`
- `apps/ios/.../CollectionDetailView.swift`
- `apps/ios/.../DeckDetailView.swift`
- `apps/ios/.../ResultsView.swift` only if needed to preserve intended behavior
- `docs/work-efforts/2026-04-10-list-visual-glitch/*`

## Risks and Open Questions

- SwiftUI `List`/`Section` behavior may still impose some rounding or header behavior that can only be influenced indirectly.
- Early debugging can easily misidentify the rendered list surface, so the final patch must be grounded in on-device verification.
- Cleanup after diagnostic changes matters here, because temporary debug visuals and version bumps can easily pollute the branch.

## Verification Plan

1. `make ios-build`
2. Manual/on-device verification for the affected Library list surfaces during swipe-to-delete and press-and-hold.
3. Confirm the Results page still keeps the sticky scanned-card count behavior.
