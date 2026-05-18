# Collections List Rounding Glitch — Compact Planning Summary

## Goal
Investigate and fix a small visual glitch in the iOS Collections list where the **top and bottom cells** appear delayed in transitioning to rounded corners during interaction states such as swipe-to-delete and press-and-hold.

## Context
- Brett compared the behavior with the iPhone Mail app and found that the general list interaction behavior is consistent.
- This reduces the scope: the issue is not that rounding happens at all, but that the top/bottom cells appear visually delayed or glitchy in the transition.
- Middle cells do not appear to show the same issue, but they should still be checked for consistency.

## Scope
- Reproduce the issue in the iOS Collections list.
- Identify the cause of the delayed or inconsistent rounding transition on top/bottom cells.
- Investigate whether middle cells are also affected in subtler ways.
- Fix the visual glitch without broad list redesign.

## Non-goals
- Redesigning list styling across the app.
- Changing standard iOS interaction behavior just because rounding occurs.
- Broad refactors outside the touched Collections list surface unless clearly necessary.

## Likely cause areas
- SwiftUI `List` row styling
- custom row background / overlay layering
- `.listRowBackground(...)`
- `.clipShape(...)`, `.cornerRadius(...)`, masking, or animation timing
- differences between first/last row rendering and middle-row rendering during interactive state changes

## Verification
- Verify behavior in simulator.
- Check top, middle, and bottom rows during swipe-to-delete.
- Check top, middle, and bottom rows during press-and-hold / long-press interaction.
- Confirm the fix is visually smoother and more consistent.
- Capture screenshots or screen recordings if helpful.

## Constraints
- Do all work in a git worktree. 
- Use native agents, not ACP thread sessions.
- Preserve current behavior outside the intended visual fix.
- Record important findings/decisions in repo docs if the investigation reveals something worth keeping.
- Reference CLAUDE.md for repo working instructions.
