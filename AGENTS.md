# AGENTS.md

Project instructions for humans and coding agents working in this repo.

## Project overview

mtg-scanner is an iPhone-first Magic: The Gathering card scanning system. SwiftUI iOS app captures and crops card images on-device, uploads to a FastAPI backend that performs AI-powered recognition (OpenAI) with MTGJSON validation, and returns structured card identifications.

## Repo layout

```
apps/ios/                    SwiftUI app with camera, card detection, cropping, upload
  MTGScanner/                Xcode app shell: entry point, Info.plist, assets, ML model
  MTGScannerKit/             Swift Package: all production source + tests (indexed by SourceKit-LSP)
  MTGScanner.xcworkspace     Workspace referencing both the app and the local package
services/api/                FastAPI backend: recognition, detection, validation, artifacts
packages/schemas/            Versioned JSON schemas and example payloads
docs/                        Plans, workflows, architecture decision records
prompts/                     AI extraction prompt templates
samples/                     Test images and ground-truth fixtures
evals/                       Evaluation harness and results
scripts/                     Bootstrap, run, and test helpers
```

## Principles

- Keep iteration local and explicit.
- Prefer small, reviewable changes — one feature or fix at a time.
- Keep prompts in `prompts/` and contracts in `packages/schemas/`.
- Avoid hiding behavior in generators or complex build tooling.
- Keep filenames and folders obvious for fast navigation.
- Prefer mocked or fixture-backed behavior until a real dependency is justified.

## Supporting rules

`AGENTS.md` is the repository's only instruction-file convention. Nested files
under `apps/ios/`, `services/api/`, and `docs/work-efforts/` add guidance for their
subtrees. Read the relevant nested file when working in that subtree.

Shared standards live in `.agents/rules/`; these are supporting documents,
not automatically applied glob rules. Paths below are relative to the repo root.

- Python changes: read `.agents/rules/python-coding-standards.md`.
- Swift changes: read `.agents/rules/swift-coding-standards.md`.
- Tests: read `.agents/rules/testing.md`.
- Detection, recognition, or cropping: read `.agents/rules/detection-recognition.md`.
- Every code review: read `.agents/rules/code-review.md`.

## Mandatory agent workflows

### Worktree requirement

All repository changes, including documentation and instructions, MUST be made
in a task-specific git worktree, never directly on main/master.

1. Fetch the remote and verify the main project branch is up to date before starting. If it is behind or diverged, notify the user for resolution. If freshness cannot be verified, report that limitation.
2. Create a worktree with a short, descriptive name: `git worktree add ../mtg-scanner-worktrees/<task-description> -b <task-description>` (e.g., `add-binder-detection`, `fix-crop-rotation`).
3. If already in a worktree for this task, proceed there. Do not reuse another task's worktree or modify its work.
4. Set up only the dependencies needed for the task and do all work in the worktree.
5. Leave the worktree, branch, local configuration, and review artifacts available for the user's manual review after completing implementation and verification.

### Worktree setup

- Documentation/instruction-only changes require no API bootstrap, data downloads, or app build.
- For backend work, run `make api-bootstrap`. Copy `services/api/.env` from the original checkout only when local configuration is needed and the file exists; never print or commit its contents. Tests use mocks and fixtures without API keys.
- Run `make api-import-ck-prices` or `make api-update-mtgjson` only when the task or manual validation needs those datasets. Do not download them for every worktree.
- For iOS-only work, set up the iOS build environment; bootstrap the backend only if integration validation needs it.

### Manual review handoff and cleanup

Implementation and verification complete means **ready for user review**.
Agent self-review, passing tests, a commit, a PR, or a merge does not authorize
worktree cleanup.

- In the final handoff, include the absolute worktree path, branch, commit hash (or uncommitted status), verification results and limitations, and the commands needed to inspect or run the changed behavior.
- Do not remove the worktree, delete its branch, or discard review artifacts unless the user explicitly requests cleanup of that worktree. Approval to merge alone is not approval to clean up.
- When cleanup is explicitly requested, check for uncommitted/untracked work and locally unique commits first. Preserve them or report them for resolution; never force removal to bypass those checks.
- After safe, authorized cleanup, report what was removed. Delete the branch only if branch deletion was also requested.

### Pre-implementation baseline and verification

Run the checks relevant to the changed subsystem before implementation and again
afterward. Setup verification counts as the baseline; do not repeat identical
checks without a change or failure that warrants it.

- Backend: `make api-test` and `make api-lint`.
- iOS: `make ios-build`, `make ios-lint`, and relevant tests via `make ios-test`.
- Cross-stack changes: run both sets (`make lint` covers both lint commands).
- Documentation/instruction-only changes: review the diff, check referenced paths/commands, and run `git diff --check`; no runtime tests or builds are required unless executable behavior changes.

Record existing baseline failures before proceeding. Fix failures introduced by
the task, and report unrelated failures without expanding scope. Do not claim a
check passed if it failed or was not run.

### Code review gate

Review every changed file before committing or handing off work. Use
`.agents/rules/code-review.md` as the canonical checklist rather than maintaining
a duplicate here. Explicitly report pass/fail for each applicable criterion;
mark inapplicable criteria N/A with a reason (e.g., runtime tests for prose-only
changes). Fix failures introduced by the change before committing.

Lint fixes must address the underlying design issue. Do not suppress or bypass a
lint rule without explicit approval.

### Commit discipline

- One logical change per commit. Do not bundle unrelated changes.
- Commit messages must state what changed and why, not just "fix" or "update."
- Run the applicable verification above before committing. Do not commit code that fails its own tests.

### Scope guard

Do not modify files or add features outside the stated task scope. If you discover something that should be fixed but is unrelated to the current task, note it in your report but do not fix it.

## Development commands

```bash
# Backend (requires uv: brew install uv)
make api-bootstrap          # create venv and install deps via uv
make api-import-ck-prices   # fetch and process product price list from card kingdom
make api-update-mtgjson     # fetch and process mtgjson data for all printings
make api-run                # start FastAPI dev server
make api-test               # run pytest suite
make api-lint               # run mypy type checking

# iOS (open workspace, not xcodeproj, to include the local package)
open apps/ios/MTGScanner.xcworkspace
make ios-build              # build the app via xcodebuild (uses workspace)
make ios-test               # run tests via xcodebuild
make ios-lint               # run SwiftLint
make ios-snapshot ROUTE=settings  # capture a PNG of a named UI route (see apps/ios/AGENTS.md)
make ios-snapshot-all       # capture all known routes

# Static analysis
make lint                   # run all static analysis (mypy + SwiftLint)

# Evaluation
PYTHONPATH=services/api python evals/run_eval.py
```

## Coding standards

### General

- Write the simplest code that satisfies the requirements.
- Prefer flat control flow over deep nesting. Functions should be < 30 lines where practical.
- Use clear names instead of comments. If a function needs a comment to explain what it does, rename it.
- No speculative code — do not add parameters, protocols, or abstractions "for future use."
- No dead code, commented-out code, or TODO placeholders in committed work.
- Type annotations are expected in both Python and Swift.

### Python (services/api)

- Python 3.14+. Use `str | None` union syntax, not `Optional[str]`.
- Pydantic models for all request/response shapes.
- `pydantic_settings.BaseSettings` for configuration with `.env` file support.
- Recognition routes are sync `def`; LLM providers use sync `httpx.Client`. Do not use `async def` with sync HTTP calls — it blocks the event loop. See `.agents/rules/python-coding-standards.md` for details.
- Custom exceptions inherit from a base in `services/api/app/services/errors.py`.
- Imports: stdlib → third-party → local, separated by blank lines.

### Swift (apps/ios)

- Swift 6.0+, SwiftUI, minimum iOS 18.0 (supports iOS 18 and iOS 26).
- MVVM architecture: Views, ViewModels (`@Observable` classes held via `@State` or passed via `@Environment`), Services.
- `final class` by default for view models and services.
- `@MainActor` for UI-bound classes. Use `Task { @MainActor in }` to dispatch from background threads.
- No force unwraps (`!`) in production code. Use `guard let` or `if let`. Use `XCTUnwrap` in tests; SwiftLint also checks test files.
- `[weak self]` in closures that capture `self` on long-lived objects.
- Camera/Vision work runs on dedicated serial `DispatchQueue`s, never the main thread.

## Testing

### Backend (pytest)

- Tests live in `services/api/tests/`.
- Use `FastAPI.TestClient` for endpoint tests.
- Use `monkeypatch` for environment overrides, `tmp_path` for isolated file system.
- Mock provider returns fixture data — tests do not require network access or API keys.
- Schema validation: `test_schema_examples.py` validates examples against JSON Schema Draft 2020-12.
- Run with: `make api-test` or `pytest services/api/tests/`.

### iOS (XCTest)

- `final class <Feature>Tests: XCTestCase` naming pattern.
- Every public method or type should have at least one test.
- Tests must exercise real code paths — no tests that only verify mocks or hardcoded values.
- Use `XCTAssertEqual` with `accuracy:` parameter for floating-point comparisons.

### Test quality rules

- Given specific inputs, verify specific outputs.
- Test edge cases: empty input, boundary values, nil/optional paths.
- A test must fail if the implementation is broken. Ask: "If I deleted the implementation body, would this test fail?"
- Do not write tests that test language features rather than your logic.

## Contract-first changes

- Update versioned schemas under `packages/schemas/v1/` first.
- Add or update matching examples under `packages/schemas/examples/v1/`.
- Keep API mocks aligned with contract examples.
- Preserve the existing response contract unless the task explicitly changes it.

## Recognition and detection work

When touching detection, recognition, or cropping:

- Test against real sample images in `samples/test/` when possible.
- Inspect artifacts under `services/.artifacts/recognitions/`.
- Check crop quality, not just card count.
- Run `make api-test` to confirm regression tests still pass.
- Verify both mock and real provider paths if the change touches provider logic.

## Provider strategy

1. `mock` — default for tests and local dev (no network, no API keys).
2. `openai` — real hosted evaluation via OpenAI API.
3. OpenAI-compatible — local models (Ollama, LM Studio) via `OPENAI_BASE_URL` + response mode.

Do not add provider-specific integrations unless the OpenAI-compatible path proves insufficient.

## Documentation

- `README.md` — project overview, quick start, provider config.
- `docs/plan.md` — strategic roadmap and phase status.
- `docs/project-brief.md` — product goals and current state.
- `docs/development-workflow.md` — local dev procedures.
- `docs/feature-workflow.md` — lean feature template for agent threads.
- `docs/decisions/` — architecture decision records (ADRs).
- `docs/plans/` — active feature plans.

Update docs alongside code when behavior or configuration changes. Record important architectural decisions as ADRs in `docs/decisions/`.

## Context compaction rules

When the user asks to compact context, first update `docs/agent-state.md`.

The compacted context must preserve:

- Current goal
- Current task
- Relevant files and symbols
- Architectural decisions
- Constraints and do-not-change rules
- Known failures, test results, and commands already run
- Next concrete steps

Prefer decisions and verified facts over discussion history.
Drop abandoned approaches unless they explain why not to repeat them.
Do not preserve unrelated implementation details.
