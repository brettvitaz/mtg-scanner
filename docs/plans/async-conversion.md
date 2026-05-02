# Plan: Convert Backend to Async

## Background

The backend currently uses sync route definitions (`def`) with sync `httpx.Client` for LLM provider calls. This was a deliberate fix for a production issue where `async def` routes calling sync HTTP clients blocked the event loop and serialized all requests — only one recognition could process at a time.

The sync-route-with-threadpool approach works correctly. This plan documents the path to a fully async architecture, which would provide better concurrency characteristics (event-loop-based concurrency vs. 40-thread threadpool limit) and align with FastAPI's intended async patterns.

## Current state

| Component | Pattern | File |
|-----------|---------|------|
| Recognition routes | sync `def` | `services/api/app/api/routes/recognitions.py` |
| Card lookup routes | `async def` (sync SQLite inside) | `services/api/app/api/routes/cards.py` |
| OpenAI provider | sync `httpx.Client` | `services/api/app/services/llm/openai_provider.py` |
| Anthropic provider | sync `httpx.Client` | `services/api/app/services/llm/anthropic_provider.py` |
| Moonshot provider | sync `httpx.Client` | `services/api/app/services/llm/moonshot_provider.py` |
| LLMProvider Protocol | sync `def recognize()` | `services/api/app/services/llm/base.py` |
| RecognitionService | sync, `ThreadPoolExecutor` for multi-crop | `services/api/app/services/recognizer.py` |
| Card detection | sync OpenCV (CPU-bound) | `services/api/app/services/card_detector.py` |
| Card validation | sync SQLite | `services/api/app/services/card_validation.py` |
| Settings | no `@lru_cache`, re-reads `.env` per call | `services/api/app/settings.py` |
| Middleware | `BaseHTTPMiddleware` | `services/api/app/main.py` |

## Conversion phases

### Phase 1: Settings caching (independent, do first)

Add `@lru_cache` to `get_settings()` in `settings.py` so it stops re-reading `.env` on every request. This is a standalone improvement regardless of async conversion.

**Files:**
- `services/api/app/settings.py` — add `from functools import lru_cache`, decorate `get_settings()`
- `services/api/tests/conftest.py` — call `get_settings.cache_clear()` in test fixtures that override env vars

### Phase 2: Convert LLM providers to async

Convert each provider's `recognize()` method from sync `httpx.Client` to async `httpx.AsyncClient`. This is the core change.

**Pattern for each provider:**
```python
# Before
def recognize(self, image_bytes, metadata, prompt_text) -> RecognitionResult:
    with httpx.Client(timeout=self._timeout) as client:
        response = client.post(url, headers=headers, json=body)
        response.raise_for_status()

# After
async def recognize(self, image_bytes, metadata, prompt_text) -> RecognitionResult:
    async with httpx.AsyncClient(timeout=self._timeout) as client:
        response = await client.post(url, headers=headers, json=body)
        response.raise_for_status()
```

**Files:**
- `services/api/app/services/llm/base.py` — change `LLMProvider` Protocol: `async def recognize(...)`
- `services/api/app/services/llm/openai_provider.py` — async `recognize()`, `httpx.AsyncClient`
- `services/api/app/services/llm/anthropic_provider.py` — async `recognize()`, `httpx.AsyncClient`
- `services/api/app/services/llm/moonshot_provider.py` — async `recognize()`, `httpx.AsyncClient`
- `services/api/app/services/recognizer.py` — `MockRecognitionProvider.recognize()` becomes `async def` (trivial, no I/O)

**Testing note:** The `RecognitionProvider` Protocol in `recognizer.py:26` must also be updated to `async def recognize()`. Test monkeypatches that replace `recognize` must return coroutines.

### Phase 3: Convert RecognitionService to async

Make `RecognitionService.recognize()` and its internal methods async.

**Key changes in `services/api/app/services/recognizer.py`:**

1. `recognize()` (line 237) — `async def`, `await` provider calls
2. `_recognize_multiple_crops()` (line 171) — replace `ThreadPoolExecutor` with `asyncio.Semaphore` + `asyncio.gather()`:

```python
# Before: ThreadPoolExecutor
executor = concurrent.futures.ThreadPoolExecutor(max_workers=self._max_concurrent_recognitions)
futures = {executor.submit(self._provider.recognize, ...): index}

# After: asyncio.Semaphore + gather
semaphore = asyncio.Semaphore(self._max_concurrent_recognitions)

async def bounded_recognize(index, crop_bytes, crop_metadata):
    async with semaphore:
        result = await self._provider.recognize(crop_bytes, crop_metadata, prompt_text)
        return index, result

tasks = [bounded_recognize(i, cb, cm) for i, (cb, cm) in enumerate(crops)]
completed = await asyncio.gather(*tasks, return_exceptions=True)
```

3. `_apply_llm_correction()` (line 96) — `async def`, `await` provider calls
4. `_validate_response()` (line 88) — keep sync (SQLite is fast), or wrap in `asyncio.to_thread()` for correctness

**CPU-bound work (OpenCV detection):**
- `card_detector.detect()` and `card_detector.crop_region()` are CPU-bound
- Wrap in `await asyncio.to_thread(self._card_detector.detect, image_bytes)` to avoid blocking the event loop

### Phase 4: Convert routes to async

Change recognition route handlers from `def` to `async def` and `await` the service calls.

**Files:**
- `services/api/app/api/routes/recognitions.py` — `async def create_recognition()`, `async def create_recognition_batch()`, `await` service calls
- `services/api/app/api/routes/cards.py` — these are already `async def`; wrap sync SQLite calls in `asyncio.to_thread()` or change to `def` (simpler, both are correct)

### Phase 5: Convert middleware to pure ASGI

Replace `BaseHTTPMiddleware` with a pure ASGI middleware for `RequestIdMiddleware`. This fixes `contextvars` propagation and removes per-request overhead.

**File:** `services/api/app/main.py`

```python
# Before
class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        ...

# After
class RequestIdMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        # ... set request_id, time the request, call self.app(scope, receive, send)
```

### Phase 6: Update rules and docs

After conversion is verified:

**Files to update:**
- `.claude/rules/python-coding-standards.md` — revert async section to prescribe `async/await`, `httpx.AsyncClient`, `asyncio.Semaphore`
- `CLAUDE.md` — update Python section to reference async patterns
- `services/api/CLAUDE.md` — update coding rules to reference async patterns
- This file — mark as completed

## Error handling during conversion

The critical invariant: **never combine `async def` routes with sync blocking calls without `asyncio.to_thread()`**. During incremental conversion, if a route is `async def` but calls a service that hasn't been converted yet, the service call must be wrapped:

```python
# Transitional pattern — remove once service is fully async
result = await asyncio.to_thread(service.recognize, image_bytes=..., metadata=...)
```

## Verification

After each phase:
1. `make api-test` — all existing tests pass
2. `make api-lint` — mypy passes (async signatures propagate through types)
3. Manual test with real provider — confirm concurrent requests are not serialized
4. Load test: send 3+ simultaneous recognition requests, verify they complete in ~1x single-request time, not ~3x

## Risks

- **Test fixture updates**: every test that monkeypatches `recognize()` must patch with an async function. High file count but mechanical.
- **`asyncio.to_thread` for OpenCV**: adds a small overhead per call. Negligible for detection (runs once per request) but worth measuring if it appears in profiling.
- **MockRecognitionProvider**: must become async. Since it does no I/O (reads a local fixture file), this is trivial but must not be forgotten.
