# Request: Library list visual glitch

**Date:** 2026-04-10
**Author:** Brett

## Goal

Fix the Library list surfaces so they no longer show the unwanted rounded-row behavior during swipe and press/hold interactions, while keeping the Results page sticky scanned-card count behavior as-is.

## Requirements

1. Identify which Library list surfaces are actually rendering the affected rows.
2. Apply the smallest change set that removes the unwanted rounded-row treatment on the affected Library surfaces.
3. Preserve expected iOS-native interaction behavior where possible.
4. Keep the sticky scanned-card count on the Results page.
5. Do all implementation and review work in a git worktree using native agents, not ACP thread sessions.

## Scope

**In scope:**
- Library top-level list styling
- collection detail list styling
- deck detail list styling
- swipe-to-delete behavior
- press-and-hold / long-press behavior where affected by list structure

**Out of scope:**
- broad app-wide list redesign
- removing the sticky scanned-card count from Results
- unrelated visual cleanup outside these Library list surfaces

## Verification

- Build the iOS app successfully.
- Verify the affected Library lists on device.
- Confirm the Results page keeps the sticky scanned-card count behavior.

## Context

Files or docs the agent should read before starting:

- `README.md`
- `CLAUDE.md`
- `docs/feature-workflow.md`
- relevant iOS Library and Results UI files
- `.claude/rules/code-review.md`

## Notes

- Early debugging showed that edits to the top-level `LibraryView` alone were not the whole story; the visible affected list also exists in the detail views.
- Brett ultimately preferred keeping the sticky scanned-card count on the Results page.
- Important findings and decisions should be recorded in repo docs when the work is completed.
- Ignore the untracked `.swift-version` file in the main repo while doing this work.
