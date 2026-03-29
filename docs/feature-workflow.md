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
1. **All code changes happen in a worktree** — never commit directly to main/master.
2. Work one feature/fix at a time.
3. **Run baseline verification** (tests/build) before making changes.
4. Make the smallest useful change that solves the problem.
5. Run verification after changes, before claiming success.
6. **Pass code review checklist** (`.claude/rules/code-review.md`) with explicit pass/fail per criterion.
7. **Commit after each feature or change** with a meaningful message (what + why).
8. Keep docs concise; avoid creating instruction sprawl.

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
- Create worktree: git worktree add ../mtg-scanner-worktrees/<task-description> -b <task-description>
- Run baseline verification before making changes

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
```

## Definition of done
A feature/change is done when ALL of these are true:
- [ ] work was done in a worktree, not on main/master
- [ ] pre-implementation baseline established (tests/build passed before changes, or failures noted)
- [ ] code implemented and matches the stated requirements
- [ ] relevant tests added or updated; tests exercise real code paths
- [ ] all tests and builds pass after changes
- [ ] code review checklist completed — each criterion stated with pass/fail
- [ ] no scope creep — only requested changes included
- [ ] artifacts/debug outputs still make sense if the change touches recognition
- [ ] docs updated if behavior/config changed
- [ ] important findings and decisions recorded in repo docs
- [ ] commit created with a meaningful message (what + why)

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
- `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`
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
