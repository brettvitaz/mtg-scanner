# Request: Collections list rounding glitch

**Date:** 2026-04-10
**Author:** Brett

## Goal

Investigate and fix a small visual glitch in the iOS Collections list where the top and bottom cells appear delayed in transitioning to rounded corners during swipe-to-delete and press-and-hold interactions.

## Requirements

1. Reproduce the issue in the Collections list and identify the cause of the delayed/glitchy rounding transition.
2. Fix the top and bottom cell transition glitch without broad redesign of list behavior.
3. Check middle cells as well and confirm they do not have the same issue, or fix them if they do.
4. Preserve expected iOS-native interaction behavior where possible.
5. Do all implementation and review work in a git worktree using native agents, not ACP thread sessions.

## Scope

**In scope:**
- Collections list row styling and interactive-state rendering
- swipe-to-delete behavior
- press-and-hold / long-press behavior
- focused iOS UI bugfix work needed to smooth the rounding transition

**Out of scope:**
- broad app-wide list redesign
- changing standard iOS interaction behavior just because rounding occurs
- unrelated visual cleanup outside the touched Collections list surface

## Verification

- Build the iOS app successfully.
- Verify top, middle, and bottom rows during swipe-to-delete.
- Verify top, middle, and bottom rows during press-and-hold / long-press.
- Capture screenshots or screen recordings if useful for review.

## Context

Files or docs the agent should read before starting:

- `README.md`
- `CLAUDE.md`
- `docs/feature-workflow.md`
- `docs/plans/collections-list-rounding-glitch.md`
- relevant iOS Collections/list UI files
- `.claude/rules/code-review.md`

## Notes

- Brett reviewed the iPhone Mail app and found the general behavior is consistent there. The issue is specifically the delayed/glitchy transition on the top and bottom cells, not the fact that rounding exists at all.
- Important findings and decisions should be recorded in repo docs when the work is completed.
- Ignore the untracked `.swift-version` file in the main repo while doing this work.
