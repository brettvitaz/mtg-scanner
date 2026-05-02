---
paths:
  - "services/api/**/*.py"
  - "scripts/**/*.py"
  - "evals/**/*.py"
---

# Python Coding Standards

## Language level
- Python 3.11+. Use modern union syntax: `str | None`, not `Optional[str]`.
- Use `list[T]`, `dict[K, V]` lowercase generics, not `List`, `Dict` from typing.

## Models and config
- All request/response shapes must be Pydantic `BaseModel` subclasses.
- All configuration must go through `pydantic_settings.BaseSettings` in `settings.py`.
- No raw `os.environ` reads in service code — use settings.
- Environment variables override `.env` file values.

## Error handling
- Custom exceptions inherit from the hierarchy in `services/api/app/services/errors.py`.
- `RecognitionConfigurationError` for setup/config issues.
- `RecognitionProviderError` for runtime provider failures.
- Never swallow exceptions silently — log or re-raise.

## Async
- Recognition routes are sync `def` — FastAPI runs them in a threadpool automatically.
- LLM providers use sync `httpx.Client` inside sync routes. This is intentional: `async def` routes with sync HTTP calls block the event loop and serialize all requests.
- Multi-crop concurrency uses `concurrent.futures.ThreadPoolExecutor` with bounded `max_workers`.
- Card lookup routes (`cards.py`) are `async def` with sync SQLite — acceptable because SQLite is local and sub-millisecond, but prefer `def` for new routes that call sync code.
- Do not use `requests` — use `httpx` (sync or async as appropriate).
- See `docs/plans/async-conversion.md` for the planned migration to fully async.

## Code organization
- Endpoint handlers must be thin — business logic belongs in `services/`.
- Imports: stdlib → third-party → local, separated by blank lines.
- Functions < 30 lines where practical.
- No speculative abstractions — build what is needed now.

## File conventions
- Scripts use `#!/usr/bin/env python3` shebang.
- Shell scripts use `set -euo pipefail` for strict error handling.
