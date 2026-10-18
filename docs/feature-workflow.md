# Feature Workflow

Short, practical workflow for implementing features in this repo. Keep this document lean so agents with smaller context windows can still use it.

## Purpose
Use this when starting a feature thread or handing work to a coding agent.

## Minimal context to load
Default reading set for feature work:
1. `README.md`
2. `docs/feature-workflow.md`

Only load more if needed:
- `services/api/README.md` for backend/provider details
- file-specific code/docs relevant to the task

This keeps the token footprint small for local agents with ~65k context windows.

## Working agreement
1. **All repository changes happen in a task-specific worktree** — never edit directly on main/master. Follow setup and verification guidance in `AGENTS.md`.
2. Work one feature/fix at a time.
3. **Run applicable baseline verification** before making changes; prose-only changes need diff and reference checks, not runtime builds.
4. Make the smallest useful change that solves the problem.
5. Run verification after changes, before claiming success.
6. **Pass code review checklist** (`.agents/rules/code-review.md`) with explicit pass/fail per criterion.
7. **Commit after each feature or change** with a meaningful message (what + why).
8. Keep docs concise; avoid creating instruction sprawl.
9. Leave the worktree, branch, and review artifacts available for manual review. Remove them only on an explicit cleanup request, following `AGENTS.md`; a merge does not authorize cleanup.

## Feature workflow skills
Three repo skills in `.agents/skills/` run this workflow in phases. Invoke them
with `/skill:<name>` in pi or `$<name>` in Codex. Text after the skill name is
passed through unchanged.

1. `feature-design <request>` discovers current requirements, shapes UI through the installed Impeccable workflow where applicable, obtains explicit design approval, and saves `tmp/feature-briefs/<name>.md`. Use the structured question mechanism available in the harness; Plan mode is not a universal prerequisite.
2. `feature-build <brief path>` reconciles later user corrections before dependent work, runs baselines, implements the effective design itself, verifies behavior, obtains independent UI finish review and documentation through Impeccable, and commits for manual review.
3. `feature-review [brief path]` sends the branch diff and effective requirements to one independent correctness reviewer, verifies findings, and reports without fixing. It does not certify native visual quality or hardware behavior.

The brief carries one requirements record with stable IDs, source/quote, kind, status and supersession. Separate user decisions from implementation choices, assumptions and open questions. Later explicit user corrections supersede older requirements: update the record and affected brief/test sections, state the consequence and proceed without asking the user to approve their instruction again. Substantial unresolved visual choices return to design without reopening settled decisions.

A portable handoff includes absolute paths to the brief, requirements record, selected direction/reference and version, approval evidence, required states and verification plan. Transfer actual gitignored briefs, temporary/external images and sidecars to a location the next session/worktree can read; verify destination files. Missing artifacts remain missing, not approved. Read only external artifacts the user authorized; do not explore unrelated worktrees.

For UI, the local skills route to [Impeccable](../.agents/skills/impeccable/SKILL.md) and its installed references instead of maintaining a parallel design process. Shape stops before direction contracts and implementation; build resumes the selected playbook and persistence steps. Whole-treatment rejection uses the applicable replacement/concept process; a settled local fix inherits the existing world. Native capture surfaces use Operate mode and iOS guidance. Builder visual inspection is bounded; independent finish review and documentation follow the installed protocol, with supported role routing or disclosed substitutes.

Keep these evidence categories separate in the handoff:

| Evidence | What it establishes |
| --- | --- |
| Behavioral tests and correctness review | Effective requirements and regressions in exercised code paths |
| Native rendered checks | Exact states captured from Simulator, including open overlays, device classes, appearance and text size |
| Independent finish review | Visual judgment at the review's actual scope; fix-list resolution alone is not whole-surface approval |
| Physical acceptance | Device evidence for lens selection, framing, focus, sharpness, gestures and performance |

A closed-button geometry test cannot resolve an oversized open popup. A user-rejected screenshot goes to a new full independent finish review with that evidence; another self-certified tweak cannot close it. Browser tools and HTML/CSS detector results do not verify SwiftUI. Missing reviewers or hardware must be disclosed without inventing a pass. Backend-only features retain the correctness workflow and skip visual work.

## Feature thread template
Each implementation thread should define:
- Goal
- Scope / non-goals
- Files or subsystem involved
- Verification plan
- Commit requirement

Suggested prompt shape:

```text
Implement [feature/fix].

Context to read:
- README.md
- docs/feature-workflow.md
- [specific files for this task]

Setup:
- Create worktree: git fetch origin && git worktree add ../mtg-scanner-worktrees/<task-description> -b <task-description> origin/main
- Run applicable baseline verification before making changes
- Preserve the worktree and branch for manual review; do not clean up automatically

Requirements:
- [bullets]

Verification:
- [tests / build / manual checks]

Constraints:
- Keep API contract unchanged unless explicitly requested
- Pass code review checklist (each criterion: pass/fail) before committing
- Commit after finishing this feature/change

Report back with:
- what changed
- baseline verification results (before changes)
- post-implementation verification results
- code review results (each criterion: pass/fail)
- commit hash
- absolute worktree path and branch
- commands to inspect or run the change for manual review
```

## Definition of done
Implementation is ready for user review when ALL applicable items are true.
Readiness does not authorize worktree cleanup:
- [ ] work was done in a worktree, not on main/master
- [ ] pre-implementation baseline established (tests/build passed before changes, or failures noted)
- [ ] code implemented and matches the stated requirements
- [ ] relevant tests added or updated; tests exercise real code paths
- [ ] UI finish review and documentation complete at the reported scope, or limitations and open findings explicit; physical acceptance reported separately
- [ ] applicable verification passes after changes; skipped checks and unrelated baseline failures are reported
- [ ] code review checklist completed — each criterion stated with pass/fail
- [ ] no scope creep — only requested changes included
- [ ] artifacts/debug outputs still make sense if the change touches recognition
- [ ] docs updated if behavior/config changed
- [ ] important findings and decisions recorded in repo docs
- [ ] commit created with a meaningful message (what + why)
- [ ] worktree, branch, and review artifacts retained; handoff includes their location and manual review commands

## Recognition-specific rules
If work touches detection/recognition:
- test against real sample images in `samples/test/` when possible
- inspect artifacts under `services/.artifacts/recognitions/`
- check crop quality, not just card count
- preserve the existing response contract unless the task explicitly changes it

## Backend verification checklist
Pick the smallest set that proves the change:
- `pytest services/api/tests`
- `curl http://127.0.0.1:8000/health`
- `curl -F "image=@..." http://127.0.0.1:8000/api/v1/recognitions`
- inspect latest `metadata.json`, `response.json`, and `crops/`

## iOS verification checklist
Pick the smallest set that proves the change:
- `make ios-build`, `make ios-lint`, and relevant tests with `make ios-test` (workspace-based commands)
- targeted simulator/manual validation when the change is UI/UX-related

## Provider strategy
Current practical order of preference:
1. `mock` for fast local/tests
2. OpenAI provider for real hosted evaluation
3. OpenAI-compatible local servers (Ollama / LM Studio) via base URL + response mode

Do not add provider-specific integrations unless the OpenAI-compatible path proves insufficient.

## Token budget guidance
To keep prompts efficient for smaller local models:
- avoid loading every doc by default
- prefer direct file pointers over broad repo summaries
- summarize prior findings in 5-10 bullets instead of pasting long transcripts
