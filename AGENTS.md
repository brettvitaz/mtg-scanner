# AGENTS.md

Repo-specific guidance for humans and coding agents.

## Principles
- Keep iteration local and explicit.
- Prefer small, reviewable changes.
- Keep prompts in `prompts/` and contracts in `packages/schemas/`.
- Avoid hiding behavior in generators or complex build tooling.

## Repo map
- `apps/ios/` — SwiftUI client scaffold
- `services/api/` — FastAPI backend scaffold
- `packages/schemas/` — versioned JSON schemas and examples
- `docs/` — architecture, workflow, ADRs
- `scripts/` — bootstrap/run/test helpers

## Working conventions
- Update docs when you change developer workflows.
- Add new API payload examples under `packages/schemas/examples/<version>/`.
- Prefer mocked or fixture-backed behavior until a real dependency is justified.
- Keep filenames and folders obvious so future agents can navigate quickly.

## Safe next steps
- Replace mocked recognition with real model integration behind `services/api/app/services/recognizer.py`.
- Add image upload wiring from iOS to the API.
- Add schema validation in API tests before expanding behavior.
