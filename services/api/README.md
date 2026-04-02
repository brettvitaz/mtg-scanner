# API Service

FastAPI backend scaffold for MTG card recognition.

## What is implemented
- `GET /health` health check
- `POST /api/v1/recognitions` multipart upload endpoint
- Pydantic response models plus explicit upload metadata model
- Config-driven recognizer service with `mock` and `openai` providers
- Local artifact logging for uploaded images and recognition responses
- Tests for endpoint behavior and schema/example validation

## Request shape
`POST /api/v1/recognitions`
- Content type: `multipart/form-data`
- Form field: `image` (required image file)
- Form field: `prompt_version` (optional string, defaults to `card-recognition.md`)

## Local run
```bash
./scripts/bootstrap-api.sh
./scripts/run-api.sh
```

The app reads local env files from:
- `services/api/.env`
- `services/api/.env.local` (if present)

You can configure the bind address and port there or via shell environment variables:

```bash
MTG_SCANNER_API_HOST=127.0.0.1
MTG_SCANNER_API_PORT=8000
```

Shell environment variables override values from `.env` files. Use `0.0.0.0` instead of `127.0.0.1` if you want the API reachable from other devices on your network.

## Multi-Card Detection

The API now supports automatic detection and recognition of multiple cards in a single image:

- Uses OpenCV to detect card boundaries based on shape and aspect ratio
- When multiple cards are detected, all card crops are prepared first, then each crop is recognized concurrently with bounded concurrency
- Detection results are saved in `metadata.json` with region coordinates
- Individual card crops are saved in the `crops/` subdirectory when multiple cards are detected

### Configuration

```bash
# Enable multi-card detection (default: true)
export MTG_SCANNER_ENABLE_MULTI_CARD=true

# Bound concurrent per-card recognition work after crop prep (default: 4)
export MTG_SCANNER_MAX_CONCURRENT_RECOGNITIONS=4

# Disable to always process the full image
export MTG_SCANNER_ENABLE_MULTI_CARD=false
```

### Detection behavior

| Cards Detected | Behavior |
|----------------|----------|
| 0 or 1 | Original image sent to recognizer as before |
| 2+ | All detected card regions are cropped first, then recognized concurrently with stable output ordering |

## Artifact logging
- Recognition uploads are saved under `.artifacts/recognitions/<timestamp>-<id>/` by default.
- Each run writes `upload.<ext>`, `response.json`, and `metadata.json`.
- `metadata.json` now also records the selected provider, model, detection results, and MTGJSON validation traces when available.
- When multiple cards are detected, individual crops are saved in `crops/card-{index}.jpg`.
- Override the base directory with `MTG_SCANNER_ARTIFACTS_DIR=/path/to/artifacts` for local debugging or eval collection.

## MTGJSON validation
The API can post-process recognizer output against a local MTGJSON index before returning the response.

### Runtime behavior
- Validation runs after provider recognition and before the API response is returned.
- The public response contract stays the same: `title`, `edition`, `collector_number`, `foil`, `confidence`, `notes`.
- When validation finds a trusted match, the response is canonicalized to MTGJSON values.
- `edition` continues to use the set name in API responses to preserve existing repo semantics.
- If the MTGJSON database is missing, validation is skipped gracefully and the raw recognizer response is returned.

### Configuration
```bash
export MTG_SCANNER_ENABLE_MTG_VALIDATION=true
export MTG_SCANNER_MTGJSON_DB_PATH=services/api/data/mtgjson/mtgjson.sqlite
export MTG_SCANNER_MTGJSON_SOURCE_PATH=tmp/AllPrintings.json
export MTG_SCANNER_MTGJSON_MAX_FUZZY_CANDIDATES=10
```

### Import workflow
Build the local SQLite index offline from `AllPrintings.json`:

```bash
PYTHONPATH=services/api ./services/api/.venv/bin/python scripts/import_mtgjson.py \
  tmp/AllPrintings.json
```

This writes:
- `services/api/data/mtgjson/mtgjson.sqlite`
- `services/api/data/mtgjson/manifest.json`

> **Note:** If you have an existing `mtgjson.sqlite` built before a schema change (e.g. the addition of the `color_identity` column), you must re-run the import script. The API will raise a `SQLite OperationalError` at startup if the database schema is stale.

## Provider configuration
The route contract stays the same. Provider selection is environment-driven:

```bash
# Default mock provider
export MTG_SCANNER_RECOGNIZER_PROVIDER=mock

# OpenAI provider
export MTG_SCANNER_RECOGNIZER_PROVIDER=openai
export OPENAI_API_KEY=your-api-key
export MTG_SCANNER_OPENAI_MODEL=gpt-4.1-mini

# General multi-card recognition setting
export MTG_SCANNER_MAX_CONCURRENT_RECOGNITIONS=4

# Optional:
export OPENAI_BASE_URL=https://api.openai.com/v1
export MTG_SCANNER_OPENAI_TIMEOUT_SECONDS=30
export MTG_SCANNER_OPENAI_RESPONSE_MODE=json_schema
```

Response modes:
- `json_schema` — best for OpenAI
- `json_mode` — OpenAI-compatible JSON mode (useful for Ollama)
- `raw` — prompt-only JSON extraction fallback (useful for LM Studio or rougher OpenAI-compatible servers)

The OpenAI-compatible provider reads the prompt file named by `prompt_version` from the repo `prompts/` directory and sends the uploaded image bytes as a data URL. Missing OpenAI env vars only fail when `MTG_SCANNER_RECOGNIZER_PROVIDER=openai`.

`MTG_SCANNER_OPENAI_TIMEOUT_SECONDS` controls the HTTP client timeout for the OpenAI-compatible recognizer and defaults to `30` seconds.

## Evaluation harness

Run fixture images against the configured recognizer and compare with ground truth:

```bash
PYTHONPATH=services/api python evals/run_eval.py
```

Fixtures live in `samples/fixtures/` and expected results live in `samples/ground-truth/`. The latest eval summary is written to `evals/results/latest.json`.

## Tests
```bash
./scripts/test-api.sh
```

## Notes
`mock` remains the default provider for tests and local development. The real provider path is covered by tests with HTTP calls stubbed, so backend tests do not require network access or live API credentials.
