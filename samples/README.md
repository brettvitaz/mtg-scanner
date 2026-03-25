# Samples

Test images and fixtures for the MTG scanner.

## Directory Structure

```
samples/
├── README.md           # This file
├── test/               # Manual testing images (gitignored, add your own)
├── fixtures/           # Committed sample images for regression tests
└── ground-truth/       # Expected recognition outputs for evals
```

## test/

Put your manual test images here. This directory is gitignored — add whatever you want for local testing.

Good candidates:
- Single clean cards for baseline testing
- Multi-card spreads for boundary detection tests
- Challenging cases (glare, sleeves, foils)

## fixtures/

Committed sample images used in automated tests. These should be:
- Small file sizes (consider compressing)
- Representative of real use cases
- Licensed appropriately (your own photos or permissive sources)

## ground-truth/

JSON files with expected recognition outputs for fixtures. Used to:
- Validate provider accuracy
- Detect regressions when changing prompts/models
- Benchmark different providers (OpenAI vs Ollama vs LM Studio)

## Naming Convention

```
samples/test/lightning-bolt-clean.jpg
samples/test/multiple-cards-table.jpg
samples/fixtures/uma-liliana-single.jpg
samples/ground-truth/uma-liliana-single.json
```

## Testing Quick Reference

```bash
# Start API with OpenAI provider
export MTG_SCANNER_RECOGNIZER_PROVIDER=openai
export MTG_SCANNER_OPENAI_MODEL=gpt-4.1-mini
./scripts/run-api.sh

# Test with curl
curl -X POST \
  -F "image=@samples/test/your-image.jpg" \
  http://localhost:8000/api/v1/recognitions
```
