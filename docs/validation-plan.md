# Validating the OpenAI Provider

## Requirements

1. **Validate OpenAI provider works** — test real image recognition end-to-end
2. **Ollama compatibility** — work with local models via Ollama's OpenAI-compatible API
3. **LM Studio compatibility** — work with LM Studio's local server

## Compatibility Analysis

| Feature | OpenAI | Ollama | LM Studio |
|---------|--------|--------|-----------|
| `json_schema` response format | ✅ Native | ⚠️ Limited/No | ⚠️ Limited/No |
| Base64 image URLs | ✅ Yes | ✅ Yes | ✅ Yes |
| `/chat/completions` endpoint | ✅ Yes | ✅ Yes | ✅ Yes |

## The Issue

The current implementation uses OpenAI's structured output with `json_schema` response format:

```python
"response_format": {
    "type": "json_schema",
    "json_schema": { ... }
}
```

Ollama and LM Studio don't fully support this. They typically expect:
- Regular `json_mode` (Ollama)
- Raw text output with JSON prompting (LM Studio)

## Proposed Solution

Add a configuration option to control response format:

```bash
# For OpenAI (default, uses json_schema)
MTG_SCANNER_RECOGNIZER_PROVIDER=openai
OPENAI_API_KEY=sk-...
MTG_SCANNER_OPENAI_MODEL=gpt-4.1-mini

# For Ollama (uses json_mode)
MTG_SCANNER_RECOGNIZER_PROVIDER=openai
OPENAI_API_KEY=ollama  # Ollama doesn't require auth but needs a value
MTG_SCANNER_OPENAI_MODEL=llama3.2-vision
OPENAI_BASE_URL=http://localhost:11434/v1
MTG_SCANNER_OPENAI_RESPONSE_MODE=json_mode

# For LM Studio (uses raw JSON prompting)
MTG_SCANNER_RECOGNIZER_PROVIDER=openai
OPENAI_API_KEY=lm-studio  # LM Studio doesn't require auth but needs a value
MTG_SCANNER_OPENAI_MODEL=your-model-name
OPENAI_BASE_URL=http://localhost:1234/v1
MTG_SCANNER_OPENAI_RESPONSE_MODE=raw
```

## Implementation Tasks

1. [ ] Add `MTG_SCANNER_OPENAI_RESPONSE_MODE` env var support
2. [ ] Implement three response format handlers:
   - `json_schema` (OpenAI native)
   - `json_mode` (Ollama compatible)
   - `raw` (LM Studio compatible, with regex extraction)
3. [ ] Test with OpenAI API
4. [ ] Test with Ollama (local)
5. [ ] Test with LM Studio (local)
6. [ ] Update docs

## Testing Checklist

### OpenAI
```bash
export MTG_SCANNER_RECOGNIZER_PROVIDER=openai
export OPENAI_API_KEY=sk-...
export MTG_SCANNER_OPENAI_MODEL=gpt-4.1-mini
export OPENAI_BASE_URL=https://api.openai.com/v1
./scripts/run-api.sh
# Upload a card image via iOS app or curl
curl -X POST -F "image=@sample.jpg" http://localhost:8000/api/v1/recognitions
```

### Ollama
```bash
# Start Ollama with a vision model
ollama run llama3.2-vision

# In another terminal
export MTG_SCANNER_RECOGNIZER_PROVIDER=openai
export OPENAI_API_KEY=ollama
export MTG_SCANNER_OPENAI_MODEL=llama3.2-vision
export OPENAI_BASE_URL=http://localhost:11434/v1
export MTG_SCANNER_OPENAI_RESPONSE_MODE=json_mode
./scripts/run-api.sh
```

### LM Studio
```bash
# Start LM Studio server on port 1234
# Load a vision-capable model

export MTG_SCANNER_RECOGNIZER_PROVIDER=openai
export OPENAI_API_KEY=lm-studio
export MTG_SCANNER_OPENAI_MODEL=your-model-name
export OPENAI_BASE_URL=http://localhost:1234/v1
export MTG_SCANNER_OPENAI_RESPONSE_MODE=raw
./scripts/run-api.sh
```
