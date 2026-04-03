# Work Effort Instructions

Standing instructions for agents working in repositories that use the work-effort framework. Merge this into your project's CLAUDE.md or AGENTS.md.

---

## Work efforts

When a `docs/work-efforts/` directory exists, follow this process for tracked work.

### Before coding

1. Check if a work-effort folder has been created for your task (look for `docs/work-efforts/YYYY-MM-DD-*/`).
2. If one exists, read `request.md` to understand the goal, requirements, and scope.
3. Fill every `[FILL:]` placeholder in `plan.md` before writing any code. Document your approach, implementation steps, files to modify, and risks.
4. Do not start coding until `plan.md` is complete.

### During coding

1. After each meaningful unit of work — file created, test passed, decision made, error encountered — append a step entry to `log.md`.
2. Use the heading + paragraph format already in the file. Increment the step number.
3. Log blocked and skipped steps, not just successes. These are valuable for review.

### After coding

1. Fill every `[FILL:]` placeholder in `review.md`.
2. Evaluate each code review criterion honestly. State pass or fail with brief evidence.
3. Compare what was requested (in `request.md`) against what was delivered. List any deferred items with reasons.
4. Paste or summarize verification command output in the Verification Results section.

### File naming

Work-effort folders follow the pattern `YYYY-MM-DD-slug` where the slug is kebab-case. Template files live in `docs/work-efforts/templates/` and should not be edited directly.
