# Plan: Collections list rounding glitch

**Planned by:** Ori
**Date:** 2026-04-10

## Approach

Treat this as a small focused iOS UI bugfix. Reproduce the Collections list interaction glitch, inspect how first and last rows are styled during swipe and long-press interactions, and make the smallest change that smooths or stabilizes the rounded-corner transition without redesigning list behavior.

## Implementation Steps

1. Read the local execution and review rules (`CLAUDE.md`, `docs/feature-workflow.md`, `.claude/rules/code-review.md`) and inspect the relevant Collections list UI files.
2. Establish a baseline:
   - `make ios-build`
   - `make ios-lint`
3. Reproduce the glitch in simulator if possible and inspect first/middle/last row behavior during:
   - swipe-to-delete
   - press-and-hold / long-press
4. Identify the minimal cause, likely in row background, clipping, masking, or animation timing for boundary rows.
5. Implement the smallest fix that preserves expected iOS-native behavior.
6. Re-run verification:
   - `make ios-build`
   - `make ios-lint`
   - targeted simulator/manual validation
7. Complete code review against `.claude/rules/code-review.md`, recording pass/fail per criterion.
8. Record any durable findings/decisions in repo docs if warranted.
9. Commit the change with a meaningful message describing what changed and why.

## Files to Modify

Likely files only, to be confirmed during investigation:

- `apps/ios/...` Collections/list UI files
- `docs/work-efforts/2026-04-10-list-visual-glitch/*`

## Risks and Open Questions

- The behavior may be partially system-driven by SwiftUI `List`, which could limit how precisely it can be tuned.
- The visible delay may come from layering or masking interactions that affect only first/last rows.
- A fix that is too aggressive could unintentionally diverge from native iOS list behavior.

## Verification Plan

1. `make ios-build`
2. `make ios-lint`
3. Manual/simulator verification for top, middle, and bottom rows during swipe-to-delete and press-and-hold.
4. Screenshots or screen recordings if useful to document before/after behavior.
