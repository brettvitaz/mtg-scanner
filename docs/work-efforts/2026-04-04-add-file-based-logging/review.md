# Review: Add File-Based Logging

**Reviewed by:** opencode
**Date:** 2026-04-04

## Summary

**What was requested:** Add file-based logging to the FastAPI backend with correlation IDs, Uvicorn integration, and logging at all critical paths (especially recognition provider communication errors).

**What was delivered:** Complete logging infrastructure with rotating file handler, console handler, request correlation IDs via contextvars, Uvicorn log routing, and logging statements across all critical paths in the recognition pipeline. 9 new tests. All existing tests still pass.

**Deferred items:** none

## Code Review Checklist

### 1. Correctness

**Result:** pass

Logging is wired correctly: `setup_logging()` called at module import in `main.py`, correlation IDs set per-request via middleware, all critical error paths in recognizer, openai_compat, routes, and validation now emit log entries. Provider HTTP errors include status code, URL, model, and response body snippet.

### 2. Simplicity

**Result:** pass

`logging_config.py` is 86 lines with flat control flow. No function exceeds 30 lines. Nesting is ≤ 2 levels. No unnecessary abstractions — just a filter class, helpers, and setup function.

### 3. No Scope Creep

**Result:** pass

Only the requested logging changes were made. No unrelated refactoring. Dead code from the review was removed (not added). The `@app.on_event` deprecation warnings are pre-existing and were not "fixed" as that would be out of scope.

### 4. Tests

**Result:** pass

9 new tests in `test_logging_config.py` exercise real code paths: logger creation, request ID generation, custom values, defaults, filter injection, idempotency, file creation, Uvicorn propagation, and caplog verification. Tests would fail if implementation broke (e.g., removing the filter would fail `test_request_id_filter_adds_attribute`).

### 5. Safety

**Result:** pass

No force unwraps. No unhandled exceptions. API keys are never logged — only URL, model name, status codes, and truncated body snippets. Thread safety correct: `contextvars` handles async request scoping, `RotatingFileHandler` is thread-safe for logging.

### 6. API Contract

**Result:** pass

Response schema unchanged. `X-Request-Id` header added to responses (additive, not breaking). Mock provider path unchanged.

### 7. Artifacts and Observability

**Result:** pass

This change IS the observability improvement. Recognition errors that were previously silent now log at WARNING or ERROR level. Correlation IDs enable tracing individual requests through the full stack. Log rotation prevents unbounded disk growth.

### 8. Static Analysis

**Result:** pass

`make api-lint` — mypy clean with no suppressions. All type annotations present.

## Verification Results

```
make api-test: 115 passed, 0 failed, 4 warnings (pre-existing FastAPI deprecation)
make api-lint: Success: no issues found in 17 source files
```

## Notes

- Code review flagged and we fixed: dead code in `recognizer.py` (duplicate unreachable block) and raw `os.environ` read instead of settings usage.
- The `MTG_SCANNER_LOG_LEVEL` setting uses lazy import of `get_settings()` inside `setup_logging()` to avoid circular dependency.
- Log directory is created at runtime with `mkdir(parents=True, exist_ok=True)` — no need to commit an empty directory.
