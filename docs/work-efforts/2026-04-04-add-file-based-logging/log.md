# Log: Add File-Based Logging

## Progress

### Step 1: Create worktree via script

**Status:** done

Ran `scripts/create-worktree.sh add-file-based-logging`. Worktree created at `../mtg-scanner-worktrees/add-file-based-logging`. Environment bootstrapped (uv install, CK prices, MTGJSON data).

Deviations from plan: none

---

### Step 2: Create logging_config.py

**Status:** done

Created `services/api/app/logging_config.py` with:
- `_RequestIdFilter` using `contextvars` for async-safe correlation IDs
- `RotatingFileHandler` (10MB, 5 backups) to `services/api/logs/app.log`
- `StreamHandler` for console output
- `setup_logging()` with idempotency guard
- `_configure_uvicorn_loggers()` to route Uvicorn logs through root handlers
- Helper functions: `get_logger()`, `set_request_id()`, `get_request_id()`

Deviations from plan: none

---

### Step 3: Update settings.py

**Status:** done

Added `mtg_scanner_log_level: str = Field(default="INFO")` to `Settings` class.

Deviations from plan: none

---

### Step 4: Update main.py

**Status:** done

Added `setup_logging()` call at module import time. Created `RequestIdMiddleware` that extracts or generates `X-Request-Id`, sets the contextvar, logs request method/path/status/duration on completion. Added startup/shutdown event handlers.

Deviations from plan: none

---

### Step 5: Update run.py

**Status:** done

Added `log_config=None` to `uvicorn.run()` to disable Uvicorn's default logging configuration.

Deviations from plan: none

---

### Step 6: Add logging to recognizer.py

**Status:** done

Added logging at all critical paths:
- `OpenAIRecognitionProvider.recognize()` — INFO for request start, ERROR for HTTP status errors (with body snippet) and connection errors, ERROR for JSON parse failures
- `_apply_llm_correction()` — WARNING for retry failures and empty correction results (previously silent)
- `_recognize_multiple_crops()` — INFO for crop count, ERROR for individual crop failures with pending count
- `recognize()` — INFO for multi-card and single-card completion with card count
- `get_recognition_service()` — INFO for provider selection, ERROR for config errors
- `_load_prompt()` — DEBUG for path, ERROR for missing file

Deviations from plan: none

---

### Step 7: Add logging to openai_compat.py

**Status:** done

Added logging for:
- `_parse_recognition_json()` — ERROR with content snippet (500 chars) on validation failure
- `_extract_openai_content()` — ERROR with available keys on malformed payload, ERROR with content preview when no JSON content found

Deviations from plan: none

---

### Step 8: Add logging to recognitions.py routes

**Status:** done

Added logging for both single and batch endpoints:
- ERROR for `RecognitionConfigurationError` with filename and content-type
- ERROR for `RecognitionProviderError` with filename and content-type

Deviations from plan: none

---

### Step 9: Add logging to card_validation.py

**Status:** done

Added WARNING log for SQLite errors during validation (previously silent fallback).

Deviations from plan: none

---

### Step 10: Create test_logging_config.py

**Status:** done

Created 9 tests covering:
- Logger creation
- Request ID generation and custom values
- Default request ID
- Request ID filter attribute injection
- Idempotency of `setup_logging()`
- Log file creation
- Uvicorn logger propagation
- Request ID in log records via `caplog`

Deviations from plan: none

---

### Step 11: Initial test and lint run

**Status:** done

First run: 2 test failures, mypy had 4 errors.

Test failures:
1. `test_get_request_id_returns_default_when_not_set` — contextvar state leaked from previous test. Fixed by explicitly resetting `_request_id.set("-")`.
2. `test_log_message_includes_request_id` — `caplog.text` uses its own format, not our formatter. Fixed by checking `caplog.records` for `request_id` attribute.

Mypy errors:
- Missing return type annotations on `dispatch`, `on_startup`, `on_shutdown`. Fixed by adding proper types and importing `RequestResponseEndpoint` and `Response` from starlette.

Deviations from plan: none

---

### Step 12: Second test and lint run

**Status:** done

All 115 tests pass. Mypy clean.

Deviations from plan: none

---

### Step 13: Code review

**Status:** done

Dispatched code-reviewer subagent. Findings:

**Critical (fixed):**
- Dead code in `recognizer.py` — duplicate unreachable block after `get_recognition_service()` returns. Removed.

**Important (fixed):**
- `logging_config.py` read log level from `os.environ` directly instead of `get_settings()`. Fixed with lazy import of `get_settings()`.

**Minor (noted):**
- Deprecation warning for `@app.on_event` — pre-existing pattern, out of scope
- `.gitignore` missing `services/api/logs/` — added

Deviations from plan: none

---

### Step 14: Final verification

**Status:** done

All review issues addressed. Updated `.gitignore` with `services/api/logs/`. Updated `.env.example` with `MTG_SCANNER_LOG_LEVEL` documentation.

Final: `make api-test` — 115 passed, 0 failed. `make api-lint` — mypy clean.

Deviations from plan: none
