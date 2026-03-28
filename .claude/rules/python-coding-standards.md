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
- Use `async/await` for all I/O-bound operations.
- Use `httpx.AsyncClient` for HTTP requests, not `requests`.
- Bounded concurrency with `asyncio.Semaphore` for parallel work.

## Code organization
- Endpoint handlers must be thin — business logic belongs in `services/`.
- Imports: stdlib → third-party → local, separated by blank lines.
- Functions < 30 lines where practical.
- No speculative abstractions — build what is needed now.

## File conventions
- Scripts use `#!/usr/bin/env python3` shebang.
- Shell scripts use `set -euo pipefail` for strict error handling.
