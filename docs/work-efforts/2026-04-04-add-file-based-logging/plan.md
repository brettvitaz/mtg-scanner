# Plan: Add File-Based Logging

**Planned by:** opencode
**Date:** 2026-04-04

## Approach

Create a centralized `logging_config.py` module that configures a root logger with both a `RotatingFileHandler` (writing to `services/api/logs/app.log`) and a `StreamHandler` (console). Request correlation IDs are propagated via `contextvars`. Uvicorn's default loggers are cleared and set to propagate through our root logger. Logging statements are added at all critical failure and state-change paths across the recognition pipeline.

## Implementation Steps

1. Create `logging_config.py` — root logger setup, correlation ID contextvar, Uvicorn routing
2. Add `mtg_scanner_log_level` to `settings.py`
3. Wire `setup_logging()` into `main.py` with request middleware for correlation IDs
4. Update `run.py` to set `log_config=None` on uvicorn
5. Add logging to `recognizer.py` — provider HTTP calls, LLM correction, concurrent crops, provider selection, prompt loading
6. Add logging to `openai_compat.py` — response parsing failures, malformed payloads
7. Add logging to `recognitions.py` routes — error context with filename/content-type
8. Add logging to `card_validation.py` — SQLite errors
9. Create `test_logging_config.py`
10. Run `make api-test && make api-lint` to verify

Steps 1-4 are foundational (must be done first). Steps 5-8 are independent and can be done in parallel. Step 9 depends on step 1. Step 10 is the gate.

## Files to Modify

| File | Change |
|------|--------|
| `services/api/app/logging_config.py` | New — logging setup, correlation IDs, Uvicorn integration |
| `services/api/app/settings.py` | Add `mtg_scanner_log_level` setting |
| `services/api/app/main.py` | Call `setup_logging()`, add `RequestIdMiddleware`, startup/shutdown events |
| `services/api/app/run.py` | Add `log_config=None` to uvicorn |
| `services/api/app/services/recognizer.py` | Add logging at critical paths |
| `services/api/app/services/openai_compat.py` | Add logging for response parsing failures |
| `services/api/app/api/routes/recognitions.py` | Add logging for error context |
| `services/api/app/services/card_validation.py` | Add logging for SQLite errors |
| `services/api/tests/test_logging_config.py` | New — tests for logging setup |
| `services/api/.env.example` | Document `MTG_SCANNER_LOG_LEVEL` |
| `.gitignore` | Add `services/api/logs/` |

## Risks and Open Questions

- **Root logger mutation in tests**: `setup_logging()` mutates the global root logger. Tests may leak state. Mitigated by idempotency guard (`_configured` flag).
- **Circular dependency**: `logging_config.py` needs settings for log level but settings shouldn't depend on logging. Resolved with lazy import inside `setup_logging()`.
- **Sensitive data in logs**: Must ensure API keys, auth headers never appear in log output. Reviewed all log statements — none include credentials.

## Verification Plan

```bash
make api-test        # 115 tests pass
make api-lint        # mypy clean
ls services/api/logs/app.log  # log file exists after app startup
```
