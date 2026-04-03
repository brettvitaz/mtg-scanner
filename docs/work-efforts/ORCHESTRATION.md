# Work Effort Orchestration Guide

How to run the work-effort process from the human side. For agent prompts, see `PROMPTS.md`.

## Workflow

```
Human                          Agent
  |                              |
  |-- 1. Create folder ----------|
  |-- 2. Fill request.md --------|
  |                              |
  |   ---- Phase Gate 1 ----     |
  |                              |
  |-- 3. Paste planning prompt ->|
  |                              |-- fills plan.md
  |                              |
  |   ---- Phase Gate 2 ----     |
  |                              |
  |-- 4. Review plan, approve -->|
  |                              |-- codes + appends log.md
  |                              |
  |   ---- Phase Gate 3 ----     |
  |                              |
  |-- 5. Paste review prompt --->|
  |                              |-- fills review.md
  |                              |
  |   ---- Phase Gate 4 ----     |
  |                              |
  |-- 6. Read review.md ---------|
  |-- 7. (Optional) Code review -|
  |-- 8. Merge or iterate -------|
```

## Step by Step

### 1. Create the work effort

```bash
./scripts/new-work-effort.sh my-feature-slug
```

This creates `docs/work-efforts/YYYY-MM-DD-my-feature-slug/` with four template files.

### 2. Fill out request.md

Open the `request.md` file and fill every `[FILL:]` placeholder. This is the only file you write. Be specific about:

- **Goal:** What should be true when this is done?
- **Requirements:** Numbered, testable statements.
- **Scope:** What's in and out. Agents respect boundaries better when they're explicit.
- **Verification:** Commands or checks that prove the work is correct.
- **Context:** File paths the agent should read before starting.

### Phase Gate 1: Request quality check

Before handing off to an agent, verify:

- [ ] Goal is a single, clear sentence
- [ ] Requirements are numbered and testable
- [ ] Scope boundaries are explicit (in and out)
- [ ] Verification section has concrete commands or checks
- [ ] Context section lists the right files (not too many, not too few)

### 3. Run the planning phase

Paste the **Phase 1: Planning** prompt from `PROMPTS.md` into an agent session. Replace `[EFFORT]` with your folder name.

The agent fills `plan.md` without writing any code.

### Phase Gate 2: Plan review

Read the agent's `plan.md` and verify:

- [ ] Approach makes sense for the requirements
- [ ] Implementation steps are concrete (not vague "refactor" or "improve")
- [ ] Files to modify are listed and changes are described
- [ ] Risks and open questions are plausible (not fabricated to fill the slot)
- [ ] Verification plan matches your verification criteria

If the plan looks wrong, correct it or ask the agent to revise before proceeding.

### 4. Run the implementation phase

Tell the agent to proceed with implementation. Include the **Phase 2: Logging** prompt from `PROMPTS.md` as a standing instruction.

The agent codes the solution and appends entries to `log.md` as it works.

### Phase Gate 3: Implementation sanity check

Before running the review phase, glance at `log.md`:

- [ ] Steps are being logged (not empty)
- [ ] No unresolved "blocked" entries
- [ ] The verification commands from `plan.md` were actually run

### 5. Run the review phase

Paste the **Phase 3: Review** prompt from `PROMPTS.md`. The agent reads all three files and fills `review.md`.

### Phase Gate 4: Review verification

Read `review.md` and verify:

- [ ] Summary accurately describes what shipped vs. what was requested
- [ ] Deferred items (if any) are justified
- [ ] Code review checklist has pass/fail for all 8 criteria with evidence
- [ ] Verification results show actual command output, not just "tests passed"
- [ ] Any failures are flagged, not hidden

### 6. (Optional) Independent code review

For important changes, paste the **Phase 4: Code Review** prompt into a separate agent session.  This gives you a second opinion from a different agent context.

### 7. Merge or iterate

If everything passes, merge the work. If not, create a follow-up request in the same work-effort folder or start a new effort.

## Tips for Weak Models

Weaker models (smaller context windows, less reliable instruction-following) can still use this system with adjustments:

- **Split phases into separate sessions.** Don't ask one session to plan, code, log, and review. Use one session per phase.
- **Accept sparse logs.** If `log.md` only has 2-3 entries instead of 10, that's fine. The review phase doesn't depend on log completeness.
- **Simplify the planning prompt.** If the model struggles with the full Phase 1 prompt, drop the "Risks" and "Files to Modify" sections and focus on just the approach and steps.
- **Pre-fill plan.md yourself.** For very weak models, fill `plan.md` yourself and skip straight to implementation + logging.
- **Use the review phase even if logging failed.** The review prompt works from request.md + the actual code changes. It doesn't require a complete log.

## When NOT to Use Work Efforts

Skip the full work-effort process for:

- Single-file bug fixes (use `docs/feature-workflow.md` instead)
- Configuration changes
- Documentation-only updates that don't involve code
- Exploratory work where the goal isn't defined yet

The overhead is worth it when: the task spans multiple files, involves handoff between agents or people, or needs an audit trail.
