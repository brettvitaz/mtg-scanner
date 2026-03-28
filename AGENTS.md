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

## Working in a git worktree

When doing code work in an isolated worktree:

### Worktree location
Place worktrees **outside** the main repo directory to avoid nested-repo issues. The recommended convention is a sibling directory:

```
/Users/brettvitaz/Development/mtg-scanner-worktrees/<branch-name>/
```

Create one with:

```bash
git worktree add ../mtg-scanner-worktrees/<branch-name> -b <branch-name>
```

### Environment setup
1. Copy the example env file into the worktree's API service directory:

   ```bash
   cp services/api/.env.example services/api/.env
   ```

2. Fill in `services/api/.env` for the task at hand. Reference the current working settings in the main repo at `services/api/.env` — the key values to carry over or adapt are:
   - `MTG_SCANNER_RECOGNIZER_PROVIDER` — use `openai` for real recognition, `mock` for offline/unit work
   - `OPENAI_API_KEY` — required when provider is `openai`
   - `MTG_SCANNER_OPENAI_MODEL` — currently `gpt-4.1-mini`
   - `OPENAI_BASE_URL` — currently `https://api.openai.com/v1`
   - `MTG_SCANNER_API_HOST` / `MTG_SCANNER_API_PORT` — set to a port that does not conflict with the main repo's running server
   - Validation and MTGJSON settings if the task touches card validation

3. Bootstrap the API (installs dependencies into a local `.venv`):

   ```bash
   bash scripts/bootstrap-api.sh
   source .venv/bin/activate
   ```

4. Run the API:

   ```bash
   uvicorn services.api.app.main:app --reload
   ```

### Cleanup
When the branch is merged or abandoned, remove the worktree:

```bash
git worktree remove ../mtg-scanner-worktrees/<branch-name>
```

## Safe next steps
- Replace mocked recognition with real model integration behind `services/api/app/services/recognizer.py`.
- Add image upload wiring from iOS to the API.
- Add schema validation in API tests before expanding behavior.
