# Work Efforts

A lightweight traceability framework that creates a chain from **what was asked** → **what was planned** → **what actually happened** → **did it match**.

## Directory Layout

Each work effort lives in its own folder under `docs/work-efforts/`:

```
docs/work-efforts/
  templates/          Blank starter files (do not edit directly)
    request.md
    plan.md
    log.md
    review.md
  PROMPTS.md          Copy-pasteable agent prompts for each phase
  ORCHESTRATION.md    Human workflow guide and phase gates
  CLAUDE.md           Standing agent instructions (portable snippet)
  2026-04-01-fix-crop-rotation/
    request.md        Human-authored: what to do and why
    plan.md           Agent-authored: how it will be done
    log.md            Agent-authored: what happened during work
    review.md         Agent-authored: did the result match the request
```

Folder names follow the pattern `YYYY-MM-DD-slug` where:
- `YYYY-MM-DD` is the creation date
- `slug` is a short kebab-case description (e.g., `fix-crop-rotation`, `add-binder-detection`)

## File Purposes

| File | Author | When | Purpose |
|------|--------|------|---------|
| `request.md` | Human | Before work starts | Defines the goal, requirements, scope, and verification criteria |
| `plan.md` | Agent | Before coding | Documents the approach, implementation steps, and files to modify |
| `log.md` | Agent | During coding | Appends progress entries as work happens |
| `review.md` | Agent | After coding | Evaluates the result against the request and code review checklist |

## Lifecycle

1. **Human** creates a work effort folder: `./scripts/new-work-effort.sh my-slug`
2. **Human** fills out `request.md` with the goal, requirements, and scope.
3. **Agent** reads `request.md` and fills `plan.md` before writing any code.
4. **Agent** works on the task, appending entries to `log.md` after each meaningful step.
5. **Agent** fills `review.md` when coding is complete, evaluating the result against the request.
6. **Human** reads `review.md` to verify the work meets expectations.

## Creating a Work Effort

Run the scaffolding script:

```bash
./scripts/new-work-effort.sh my-feature-slug
```

This creates `docs/work-efforts/YYYY-MM-DD-my-feature-slug/` with all four template files ready to fill.

## When to Use Work Efforts

Use a work effort when:
- The task spans multiple files or subsystems
- You want a traceable record of what was requested vs. what shipped
- The work will be handed off to an agent (or between agents)
- You need to review or audit the work later

For simple, single-file changes, the [feature workflow](../feature-workflow.md) is sufficient.

## For Human Reviewers

After an agent completes work:

1. Read `review.md` first — it summarizes what shipped and flags any deviations or deferred items.
2. Check the **Code Review Checklist** section for pass/fail on each criterion.
3. Compare `request.md` requirements against the **Summary** section in `review.md` to confirm nothing was missed.
4. If `log.md` exists, scan it for any "blocked" or "skipped" entries that may need follow-up.

## For Code Review Agents

When reviewing a work effort:

1. Load `request.md` to understand the original requirements.
2. Load `review.md` to see the implementing agent's self-assessment.
3. Review the actual code changes (diffs) against the criteria in `.claude/rules/code-review.md`.
4. Flag any discrepancies between what `review.md` claims and what the code actually does.
5. Verify the **Deferred items** section — anything deferred should be justified, not just forgotten.
