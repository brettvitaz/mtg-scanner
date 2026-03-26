# Feature Workflow

Short, practical workflow for implementing features in this repo. Keep this document lean so agents with smaller context windows can still use it.

## Purpose
Use this when starting a feature thread or handing work to a coding agent.

## Minimal context to load
Default reading set for feature work:
1. `README.md`
2. `docs/architecture.md`
3. `docs/feature-workflow.md`

Only load more if needed:
- `services/api/README.md` for backend/provider details
- `docs/agent-workflow.md` for prior findings/debugging history
- file-specific code/docs relevant to the task

This keeps the token footprint small for local agents with ~65k context windows.

## Working agreement
1. Work one feature/fix at a time.
2. Make the smallest useful change that solves the problem.
3. Run verification before claiming success.
4. **Commit after each feature or change.**
5. Prefer native subagents over ACP for async orchestration until ACP completion relay is reliable.
6. Keep docs concise; avoid creating instruction sprawl.

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
- docs/architecture.md
- docs/feature-workflow.md
- [specific files for this task]

Requirements:
- [bullets]

Verification:
- [tests / build / manual checks]

Constraints:
- Keep API contract unchanged unless explicitly requested
- Commit after finishing this feature/change

Report back with:
- what changed
- verification results
- commit hash
```

## Definition of done
A feature/change is done when all of these are true:
- code implemented
- relevant tests/build/manual checks pass
- artifacts/debug outputs still make sense if the change touches recognition
- docs updated if behavior/config changed
- commit created

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
- use `docs/agent-workflow.md` as deep history, not required startup context
