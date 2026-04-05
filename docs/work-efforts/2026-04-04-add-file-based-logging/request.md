# Request: Add File-Based Logging

**Date:** 2026-04-04
**Author:** opencode

## Goal

Add structured, file-based logging to the FastAPI backend. Currently there is zero logging — no log files, no logger instances, no log statements anywhere in the codebase. Recognition failures due to communication errors with the provider are completely invisible.

## Requirements

1. Log output to a rotating log file (`services/api/logs/app.log`, 10MB, 5 backups)
2. Console output preserved alongside file output
3. Request correlation IDs (UUID per request) for tracing through the full stack
4. Uvicorn logs routed through the same handlers (no split stdout/file logging)
5. Log level configurable via `MTG_SCANNER_LOG_LEVEL` env var
6. INFO, WARNING, ERROR, and DEBUG levels used appropriately
7. Recognition provider communication errors logged with full context (URL, model, status code, response body snippet)
8. LLM correction retry failures logged (currently silently swallowed)
9. Concurrent crop failures logged with index and pending count
10. No sensitive data (API keys) in logs

## Scope

**In scope:**
- New `logging_config.py` module
- Logging at all critical paths in recognizer, openai_compat, recognitions routes, card_validation
- Request middleware with correlation ID
- Uvicorn log routing integration
- Tests for logging setup
- `.env.example` documentation

**Out of scope:**
- Distributed tracing or external log aggregation
- Changing FastAPI's deprecated `@app.on_event` to lifespan (pre-existing, not introduced by this change)
- iOS app logging changes

## Verification

- `make api-test` — all 115 tests pass
- `make api-lint` — mypy clean
- Log file created at `services/api/logs/app.log` on app startup
- Request correlation IDs appear in log entries

## Context

- `services/api/app/services/recognizer.py` — provider abstraction, recognition pipeline
- `services/api/app/services/openai_compat.py` — OpenAI request/response parsing
- `services/api/app/api/routes/recognitions.py` — endpoint handlers
- `services/api/app/services/card_validation.py` — MTGJSON validation
- `services/api/app/main.py` — FastAPI app setup
- `services/api/app/run.py` — Uvicorn entry point

## Notes

- Uvicorn's default logging was disabled via `log_config=None` and routed through our handlers
- Correlation IDs use `contextvars` for async-safe request scoping
- Log directory created with `mkdir(parents=True, exist_ok=True)` — no need to commit empty dir
