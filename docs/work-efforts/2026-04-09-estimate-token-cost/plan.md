# Plan: Estimate Token Cost

**Planned by:** Claude Sonnet 4.6
**Date:** 2026-04-10

## Approach

Add a `TokenUsage` model that normalizes token counts from all three API formats, and a `RecognitionResult` wrapper that pairs a `RecognitionResponse` with its usage. Each provider extracts and returns usage from the raw API payload. `RecognitionService` accumulates usage across all LLM calls (initial crops + correction retries) and passes the total to the artifact store alongside the upload file size and a cost estimate computed from a hardcoded pricing table. The iOS app and API response contract are untouched.

## Implementation Steps

1. **Add models** — `TokenUsage`, `RecognitionResult`, `accumulate_usage()` in `models/recognition.py`.
2. **Update `LLMProvider` protocol and base helpers** — change return type to `RecognitionResult`; add `extract_openai_usage()` and `extract_anthropic_usage()` in `base.py`. (Depends on step 1.)
3. **Update each provider** — OpenAI, Anthropic, Moonshot each extract usage from their response payload and return `RecognitionResult`. Mock provider returns synthetic `TokenUsage(1500, 500, 2000)`. (Depends on step 2.)
4. **Update `RecognitionService`** — `_recognize_multiple_crops()` returns `list[RecognitionResult]`; `_apply_llm_correction()` collects correction usage; `recognize()` accumulates all usage and adds it as a 5th return element. (Depends on steps 1–3.)
5. **Add pricing module** — `services/llm/pricing.py` with `MODEL_PRICES` dict and `estimate_cost()`. Prices sourced from provider pricing pages at commit time. (Independent; can run in parallel with step 4.)
6. **Update artifact store and routes** — `save_recognition()` accepts `usage` and `estimated_cost_usd`; adds `file_size_bytes` to `metadata_dict`. Route handlers call `estimate_cost()` and pass results through. (Depends on steps 4–5.)
7. **Tests** — new `test_pricing.py`; update provider, correction, multi-card, and endpoint tests to use `RecognitionResult`. (Depends on steps 1–6.)

## Files to Modify

| File | Change |
|------|--------|
| `services/api/app/models/recognition.py` | Add `TokenUsage`, `RecognitionResult`, `accumulate_usage()` |
| `services/api/app/services/llm/base.py` | Update protocol return type; add `extract_openai_usage`, `extract_anthropic_usage` |
| `services/api/app/services/llm/openai_provider.py` | Return `RecognitionResult`; call `extract_openai_usage` |
| `services/api/app/services/llm/anthropic_provider.py` | Return `RecognitionResult`; call `extract_anthropic_usage` |
| `services/api/app/services/llm/moonshot_provider.py` | Return `RecognitionResult`; call `extract_openai_usage` |
| `services/api/app/services/recognizer.py` | Update protocol, `MockRecognitionProvider`, `RecognitionService` |
| `services/api/app/services/artifact_store.py` | Add `usage`, `estimated_cost_usd`, `file_size_bytes` to metadata |
| `services/api/app/api/routes/recognitions.py` | Unpack 5-tuple; call `estimate_cost`; pass to artifact store |
| `services/api/app/services/llm/pricing.py` | **New file** — `MODEL_PRICES`, `estimate_cost()` |
| `services/api/tests/test_pricing.py` | **New file** — pricing tests |
| `services/api/tests/test_llm_providers.py` | Update to `RecognitionResult`; add usage extraction tests |
| `services/api/tests/test_recognitions.py` | Update fake providers; verify `metadata.json` fields |
| `services/api/tests/test_card_correction.py` | Update fake providers; update tuple unpacking |
| `services/api/tests/test_multi_card.py` | Update fake providers; update tuple unpacking |

## Risks and Open Questions

- **Multi-path accumulation**: Usage must be collected from both the crop recognition path and the LLM correction path. The `accumulate_usage()` helper handles `None` entries gracefully so missing usage from one path doesn't zero out the total.
- **mypy scope conflict**: Both the multi-card and single-card branches define a `correction_usage` variable in the same function scope. Resolved by renaming the single-card variable to `single_correction_usage`.
- **Database storage**: Deferred. Artifact files are sufficient for now. If query-able history is needed later, a SQLite table mirroring the `metadata.json` fields would be the natural next step.

## Addendum 2026-04-10: Pricing refresh and auto-update

### Additional files

| File | Change |
|------|--------|
| `services/api/data/pricing/model_prices.json` | **New** — checked-in fallback; auto-refreshed by the make command and background loop |
| `services/api/app/services/llm/pricing_refresh.py` | **New** — `PROVIDER_ALLOWLIST`, `extract_prices()`, `write_prices()`, `refresh_prices_from_upstream()`, `RefreshResult` |
| `services/api/app/services/llm/pricing_loop.py` | **New** — `pricing_refresh_loop(interval_hours)` async loop |
| `services/api/app/api/routes/admin.py` | **New** — token-gated `POST /admin/pricing/refresh` |
| `scripts/update_llm_pricing.py` | **New** — thin CLI wrapper (`make api-update-pricing`) |
| `services/api/app/settings.py` | Add `mtg_scanner_pricing_refresh_interval_hours`, `mtg_scanner_admin_token` |
| `services/api/app/main.py` | Background task lifecycle (startup/shutdown); conditional admin router mount |
| `services/api/.env.example` | Document new settings |
| `services/api/app/services/llm/pricing.py` | Rewrite: remove hardcoded `MODEL_PRICES`; add `load_prices()` with mtime-aware cache; keep `estimate_cost()` signature unchanged |
| `services/api/tests/test_pricing.py` | Add `TestLoadPrices` class (mtime cache, missing file, malformed file) |
| `services/api/tests/test_pricing_refresh.py` | **New** — extract, write, refresh, tiered pricing shapes |
| `services/api/tests/test_pricing_loop.py` | **New** — loop runs immediately, survives failure, cancels cleanly |
| `services/api/tests/test_admin_pricing.py` | **New** — token auth, 502 on failure, 404 when router not mounted |
| `services/api/tests/test_startup_pricing_refresh.py` | **New** — startup/shutdown wiring |

### Key design decisions

- **Provider-level allowlist** (`PROVIDER_ALLOWLIST = frozenset({"openai", "anthropic", "moonshotai"})`): every model from these providers is imported automatically. New model releases need no code change — the next daily refresh picks them up. Adding a new provider is a one-line edit to the frozenset.
- **mtime-aware cache** in `load_prices()`: any refresh path writes the file; every uvicorn worker reloads on the next `estimate_cost()` call. No IPC, no restart required.
- **Upstream price shapes**: pydantic/genai-prices uses three formats — plain numbers, tiered dicts `{"base": N, "tiers": [...]}`, and list-of-schedules. `extract_prices()` handles all three, using the base/unconstrained rate. Models without `input_mtok`/`output_mtok` (embeddings, TTS, image) are skipped silently.
- **Admin router conditional mount**: if `mtg_scanner_admin_token` is not set, the admin router is never mounted (404, not 401 — no surface to probe).
- **Atomic writes**: `write_prices()` uses `tempfile.mkstemp` + `os.replace` so readers never see a partial file.

## Verification Plan

```bash
make api-test   # 174 passing, 2 pre-existing failures unrelated to this feature
make api-lint   # mypy: no issues found in 22 source files
```

Manual: POST an image to `/api/v1/recognitions` with the mock provider, inspect `.artifacts/recognitions/<run_id>/metadata.json`:
```json
{
  "file_size_bytes": <int>,
  "usage": {"input_tokens": 1500, "output_tokens": 500, "total_tokens": 2000},
  "estimated_cost_usd": null
}
```
`estimated_cost_usd` is `null` for the mock provider because the mock model name is `null`, which is not in `MODEL_PRICES`. For a real provider run, it will be a float rounded to 6 decimal places.
