# CLAUDE.md

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

## Mandatory agent workflows

### Worktree requirement
All code changes MUST be made in a git worktree, never directly on main/master. Before writing any code:

0. Make sure the main project branch is up to date before starting. If it is not, notify the user for resolution.
1. Create a worktree with a descriptive name: `git worktree add ../mtg-scanner-worktrees/<task-description> -b <task-description>`
2. The name must be a short description of the work (e.g., `add-binder-detection`, `fix-crop-rotation`). No generic names like `feature-1` or `dev`.
3. Bootstrap the worktree environment (see "Worktree setup reference" below).
4. Do all work in the worktree.
5. Clean up when done: `git worktree remove ../mtg-scanner-worktrees/<task-description>`

If you are already in a worktree, proceed. If you are on main/master, create a worktree first. No exceptions.

After creating a worktree:

1. Copy configuration files to the worktree: `cp services/api/.env <worktree-directory>/services/api/.env`
2. Bootstrap the api in the worktree: `make api-bootstrap && make api-import-ck-prices && make api-update-mtgjson`
3. Verify the worktree environment works: `make api-test && make api-lint`

### Pre-implementation baseline

Before making any code changes, run the relevant test/build commands to establish a passing baseline:

- Backend: `make api-test && make api-lint`
- iOS: `make ios-build` (or `xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`)
- Static analysis: `make lint` (runs mypy + SwiftLint)

If the baseline is already failing, note the failures before proceeding so you do not introduce confusion about what you broke vs. what was already broken.

### Code review gate

All code changes MUST pass a code review before the work is considered done. After implementation, review every changed file against `.claude/rules/code-review.md`. Explicitly state each criterion with pass/fail:

1. **Complexity** — functions < 30 lines, nesting ≤ 3 levels, no unnecessary abstractions.
2. **Correctness** — implementation matches the spec, edge cases handled.
3. **Tests** — new/changed code has tests that exercise real code paths and would fail if the implementation were broken.
4. **Best practices** — no force unwraps (Swift), no unhandled exceptions (Python), no scope creep, no dead code.
5. **Static analysis** — `make lint` passes. For Python-only changes run `make api-lint`; for Swift-only changes run `make ios-lint`.

Fix any failures before committing.

### Commit discipline

- One logical change per commit. Do not bundle unrelated changes.
- Commit messages must state what changed and why, not just "fix" or "update."
- Run verification (tests/build) before committing. Do not commit code that fails its own tests.

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

- Python 3.11+. Use `str | None` union syntax, not `Optional[str]`.
- Pydantic models for all request/response shapes.
- `pydantic_settings.BaseSettings` for configuration with `.env` file support.
- async/await for I/O-bound operations.
- Custom exceptions inherit from a base in `services/api/app/services/errors.py`.
- Imports: stdlib → third-party → local, separated by blank lines.

### Swift (apps/ios)

- Swift 6.0+, SwiftUI, minimum iOS 18.0 (supports iOS 18 and iOS 26).
- MVVM architecture: Views, ViewModels (`@Observable` classes held via `@State` or passed via `@Environment`), Services.
- `final class` by default for view models and services.
- `@MainActor` for UI-bound classes. Use `Task { @MainActor in }` to dispatch from background threads.
- No force unwraps (`!`) in production code. Use `guard let` or `if let`. Force unwraps are acceptable in tests.
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

- Tests live in `apps/ios/MTGScannerTests/`.
- `final class <Feature>Tests: XCTestCase` naming pattern.
- Every public method or type should have at least one test.
- Tests must exercise real code paths — no tests that only verify mocks or hardcoded values.
- Use `XCTAssertEqual` with `accuracy:` parameter for floating-point comparisons.

### Test quality rules

- Given specific inputs, verify specific outputs.
- Test edge cases: empty input, boundary values, nil/optional paths.
- A test must fail if the implementation is broken. Ask: "If I deleted the implementation body, would this test fail?"
- Do not write tests that test language features rather than your logic.

## Code review checklist

When reviewing changes (your own or others'):

1. **Correctness** — Does it do what the spec says? Edge cases handled?
2. **Simplicity** — Is there a simpler way? Functions < 30 lines? Nesting ≤ 3 levels?
3. **No scope creep** — Only implements what was requested? No "while I'm here" changes?
4. **Tests exist and are meaningful** — Cover the change? Would fail if implementation broke?
5. **No force unwraps** (Swift) or unhandled exceptions (Python) in production code.
6. **Thread safety** — Shared mutable state properly synchronized? Camera/Vision on correct queue?
7. **API contract preserved** — Response schema unchanged unless explicitly requested?
8. **Artifacts/logging** — Recognition changes still produce useful debug artifacts?

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
