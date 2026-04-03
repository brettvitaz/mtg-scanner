# Work Effort Prompts

Copy-pasteable prompt blocks for each phase of a work effort. Each prompt is self-contained — paste it into a new agent session with the file paths adjusted for your work effort folder.

No orchestration guidance here — see `ORCHESTRATION.md` for the human workflow.

---

## Phase 1: Planning

Use this prompt after the human has filled out `request.md`. The agent reads the request and fills `plan.md`.

```text
Read the work effort request and create an implementation plan.

Files to read:
- docs/work-efforts/[EFFORT]/request.md

Task:
1. Read request.md carefully. Understand the goal, requirements, scope boundaries, and verification criteria.
2. Open docs/work-efforts/[EFFORT]/plan.md.
3. Fill every [FILL:] placeholder in plan.md:
   - Approach: summarize your strategy in 2-5 sentences.
   - Implementation Steps: numbered list of concrete steps. Note dependencies between steps.
   - Files to Modify: table of file paths and what changes in each.
   - Risks and Open Questions: anything uncertain or needing human input.
   - Verification Plan: specific commands drawn from the request's verification section.
4. Do NOT start coding. Only produce the plan.

If anything in the request is ambiguous, list it under Risks and Open Questions rather than guessing.
```

---

## Phase 2: Logging

Use this prompt as a standing instruction during implementation. The agent appends to `log.md` after each significant step.

```text
You are working on a task with an active work effort log.

Standing instruction — after each meaningful unit of work (file created, test passed, decision made, error encountered):

1. Open docs/work-efforts/[EFFORT]/log.md.
2. Append a new step section using this format:

   ### Step N: [short description]

   **Status:** done | in-progress | blocked | skipped

   [1-3 sentences: what happened, what changed, commands run]

   Deviations from plan: [none, or describe what changed and why]

3. Increment the step number from the last entry.
4. Continue working.

Do not skip logging when something goes wrong — blocked and skipped entries are valuable.
```

---

## Phase 3: Review

Use this prompt after the agent finishes coding. The agent reads all three files and fills `review.md`.

```text
The implementation is complete. Perform a self-review of the work effort.

Files to read:
- docs/work-efforts/[EFFORT]/request.md (what was asked)
- docs/work-efforts/[EFFORT]/plan.md (what was planned)
- docs/work-efforts/[EFFORT]/log.md (what happened)

Task:
1. Open docs/work-efforts/[EFFORT]/review.md.
2. Fill every [FILL:] placeholder:
   - Summary: compare what was requested vs. what was delivered. List any deferred items with reasons.
   - Code Review Checklist: evaluate each of the 8 criteria (Correctness, Simplicity, No Scope Creep, Tests, Safety, API Contract, Artifacts, Static Analysis). State pass or fail with brief evidence for each.
   - Verification Results: paste or summarize the output of verification commands.
   - Notes: anything the reviewer or next agent should know.
3. Be honest. If a criterion fails, say so — do not rationalize a pass.
4. If log.md has blocked or skipped entries, address them in the review.
```

---

## Phase 4: Code Review (separate agent)

Use this prompt in a separate agent session to review someone else's (or another agent's) completed work.

```text
Review a completed work effort against the project's code review standards.

Files to read:
- docs/work-efforts/[EFFORT]/request.md (original requirements)
- docs/work-efforts/[EFFORT]/review.md (implementing agent's self-assessment)
- .claude/rules/code-review.md (review criteria)
- The actual code changes (diffs or changed files listed in the plan)

Task:
1. Read request.md to understand what was asked.
2. Read review.md to see the implementing agent's self-assessment.
3. Review each changed file against the 8 criteria in .claude/rules/code-review.md.
4. For each criterion, state whether you agree with the implementing agent's assessment.
5. Flag any discrepancies — places where review.md claims "pass" but the code suggests otherwise.
6. Check the Deferred Items section — is each deferral justified?
7. Produce a summary: approve, request changes, or flag concerns.

Be specific. Reference file paths and line numbers when flagging issues.
```
