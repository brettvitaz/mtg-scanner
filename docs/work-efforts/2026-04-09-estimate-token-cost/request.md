# Request: Estimate Token Cost

**Date:** 2026-04-09
**Author:** Brett Vitaz

## Goal

Calls to the LLM providers should have their token usage and estimated cost tracked for debug and auditing. The size of the upload file should also be tracked. This information should be persisted somewhere accessible — the `.artifacts` directory is a natural fit, but a database could be a better long-term solution.

## Requirements

1. Capture token usage (input tokens, output tokens, total) from each LLM provider call.
2. Capture upload file size in bytes.
3. Estimate the USD cost of each recognition based on token counts and model pricing.
4. Store this data in a location suitable for debug and auditing.
5. Identify reliable sources for token cost data for each supported provider.

## Scope

**In scope:**
- Token usage extraction from OpenAI, Anthropic, and Moonshot provider responses.
- Normalized internal model (`TokenUsage`) shared across providers.
- Cost estimation from a hardcoded pricing table with documented sources.
- Storing usage, cost, and file size in the per-recognition `metadata.json` artifact.
- Mock provider returning synthetic usage so tests exercise the full pipeline.

**Out of scope:**
- Database storage (noted as a future option, not implemented).
- Surfacing usage or cost in the API response or iOS app.
- Automatic alerting when cost thresholds are exceeded.
- Per-request budget enforcement.

## Addendum 2026-04-10: Pricing refresh

**Additional requirements:**

1. Pricing data must not be hardcoded in source — it should live in a config file or database loaded at runtime.
2. Prices should refresh automatically without restarting the app: **background loop** (daily, immediate first refresh on startup) and an **admin HTTP endpoint** for on-demand triggering.
3. Prices must also be updatable via a **make command** for one-off or CI use.
4. Kimi/Moonshot pricing must be sourced from a verified external source.
5. New model releases must be tracked automatically — no code change required when a provider ships a new model.

**Decisions:**
- Upstream source: [pydantic/genai-prices](https://github.com/pydantic/genai-prices) (MIT licensed) — covers all three providers.
- Local JSON file (`services/api/data/pricing/model_prices.json`) as runtime source of truth, checked in as the offline fallback.
- Provider-level allowlist (`PROVIDER_ALLOWLIST = frozenset({"openai", "anthropic", "moonshotai"})`) so new models flow through automatically on the next daily refresh.
- mtime-aware cache in `load_prices()` — any refresh path (loop, endpoint, CLI) writes the file and all workers pick up the change on their next `estimate_cost()` call.

## Verification

```bash
make api-test   # all existing and new tests pass
make api-lint   # mypy passes
```

Manual: run with mock provider, inspect `.artifacts/recognitions/<run_id>/metadata.json` — should contain `file_size_bytes`, `usage`, and `estimated_cost_usd`.

## Context

Files the agent should read before starting:

- `services/api/app/services/llm/openai_provider.py`
- `services/api/app/services/llm/anthropic_provider.py`
- `services/api/app/services/llm/moonshot_provider.py`
- `services/api/app/services/llm/base.py`
- `services/api/app/services/recognizer.py`
- `services/api/app/services/artifact_store.py`
- `services/api/app/api/routes/recognitions.py`
- `services/api/app/models/recognition.py`
