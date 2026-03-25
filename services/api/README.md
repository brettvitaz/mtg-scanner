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

## Multi-Card Detection

The API now supports automatic detection and recognition of multiple cards in a single image:

- Uses OpenCV to detect card boundaries based on shape and aspect ratio
- When multiple cards are detected, each card is cropped and recognized individually
- Detection results are saved in `metadata.json` with region coordinates
- Individual card crops are saved in the `crops/` subdirectory when multiple cards are detected

### Configuration

```bash
# Enable multi-card detection (default: true)
export MTG_SCANNER_ENABLE_MULTI_CARD=true

# Disable to always process the full image
export MTG_SCANNER_ENABLE_MULTI_CARD=false
```

### Detection behavior

| Cards Detected | Behavior |
|----------------|----------|
| 0 or 1 | Original image sent to recognizer as before |
| 2+ | Each detected card region is cropped and recognized individually |

## Artifact logging
- Recognition uploads are saved under `.artifacts/recognitions/<timestamp>-<id>/` by default.
- Each run writes `upload.<ext>`, `response.json`, and `metadata.json`.
- `metadata.json` now also records the selected provider, model, and detection results when available.
- When multiple cards are detected, individual crops are saved in `crops/card-{index}.jpg`.
- Override the base directory with `MTG_SCANNER_ARTIFACTS_DIR=/path/to/artifacts` for local debugging or eval collection.

## Provider configuration
The route contract stays the same. Provider selection is environment-driven:

```bash
# Default mock provider
export MTG_SCANNER_RECOGNIZER_PROVIDER=mock

# OpenAI provider
export MTG_SCANNER_RECOGNIZER_PROVIDER=openai
export OPENAI_API_KEY=your-api-key
export MTG_SCANNER_OPENAI_MODEL=gpt-4.1-mini
# Optional:
export OPENAI_BASE_URL=https://api.openai.com/v1
```

The OpenAI provider reads the prompt file named by `prompt_version` from the repo `prompts/` directory and sends the uploaded image bytes as a data URL. Missing OpenAI env vars only fail when `MTG_SCANNER_RECOGNIZER_PROVIDER=openai`.

## Tests
```bash
./scripts/test-api.sh
```

## Notes
`mock` remains the default provider for tests and local development. The real provider path is covered by tests with HTTP calls stubbed, so backend tests do not require network access or live API credentials.
