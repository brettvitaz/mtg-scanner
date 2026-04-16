# Backend — services/api

FastAPI backend for MTG card recognition, detection, and validation.

## Architecture

```
app/
  main.py              FastAPI app setup and middleware
  run.py               Uvicorn entry point
  settings.py          Pydantic BaseSettings config (reads .env, .env.local)
  models/
    recognition.py     Pydantic models: RecognitionResponse, RecognizedCard, etc.
  api/routes/
    health.py          GET /health
    recognitions.py    POST /api/v1/recognitions, POST /api/v1/recognitions/batch
    cards.py           GET /api/v1/cards/printings — all printings of a card by name
  services/
    recognizer.py      Provider abstraction (MockRecognitionProvider, OpenAIRecognitionProvider)
    card_detector.py   OpenCV-based multi-card detection and cropping
    card_validation.py MTGJSON post-recognition validation, normalization, and metadata enrichment
    mtgjson_index.py   SQLite-backed card/set lookup
    artifact_store.py  Local artifact logging for debugging and evals
    openai_compat.py   OpenAI API request construction
    errors.py          Custom exception hierarchy
```

## Key patterns

- **Provider selection** is config-driven via `MTG_SCANNER_RECOGNIZER_PROVIDER` env var. Mock is the default.
- **Recognition flow**: upload → optional multi-card detection/cropping → per-card recognition → MTGJSON validation → response.
- **Multi-card**: All crops are prepared first, then recognized concurrently with bounded concurrency (`MTG_SCANNER_MAX_CONCURRENT_RECOGNITIONS`).
- **Validation**: Post-recognition normalization against local SQLite MTGJSON index. Gracefully skipped if DB is missing.
- **Artifacts**: Every recognition saves upload, crops, response, and metadata under `.artifacts/`.

## Coding rules

- All new models must be Pydantic `BaseModel` subclasses.
- Settings must go through `settings.py` — no raw `os.environ` reads in service code.
- New exceptions inherit from `RecognitionConfigurationError` or `RecognitionProviderError`.
- Recognition routes are sync `def` with sync `httpx.Client`. Do not combine `async def` routes with sync HTTP calls — it serializes all requests. See `.claude/rules/python-coding-standards.md`.
- Keep endpoint handlers thin — business logic belongs in `services/`.

## Testing

```bash
make api-test
# or directly:
pytest services/api/tests/ -v
```

- `conftest.py` has shared fixtures including `mtgjson_db` (temporary SQLite for validation tests).
- Endpoint tests use `FastAPI.TestClient` — no real server needed.
- Mock provider returns data from `packages/schemas/examples/v1/recognition-response.sample.json`.
- Tests must not require network access or API credentials.
- When adding detection/crop logic, add regression tests with real sample images from `samples/test/`.

## Configuration

See `.env.example` for all available settings. Key variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `MTG_SCANNER_RECOGNIZER_PROVIDER` | `mock` | Provider selection |
| `MTG_SCANNER_ENABLE_MULTI_CARD` | `true` | Multi-card detection |
| `MTG_SCANNER_MAX_CONCURRENT_RECOGNITIONS` | `4` | Bounded concurrency |
| `MTG_SCANNER_ENABLE_MTG_VALIDATION` | `true` | MTGJSON validation |
| `MTG_SCANNER_OPENAI_RESPONSE_MODE` | `json_schema` | Response format mode |
| `MTG_SCANNER_OPENAI_TIMEOUT_SECONDS` | `30` | HTTP client timeout |
