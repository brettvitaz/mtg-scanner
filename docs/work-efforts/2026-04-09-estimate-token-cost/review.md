# Review: Estimate Token Cost

**Reviewed by:** Claude Sonnet 4.6
**Date:** 2026-04-10

## Summary

**What was requested:** Track LLM token usage, upload file size, and estimated USD cost for each recognition call, stored for debug and auditing.

**What was delivered:** All three providers now extract token counts from API responses and return them wrapped in `RecognitionResult`. `RecognitionService` accumulates usage across crops and correction calls. Each recognition artifact's `metadata.json` now includes `file_size_bytes`, a `usage` dict, and `estimated_cost_usd`. A new `pricing.py` module provides hardcoded per-model rates with documented sources.

**Deferred items:** Database storage — noted as a future option in the request; not implemented. Artifact files are sufficient for the stated auditing goal.

## Code Review Checklist

### 1. Correctness

**Result:** pass

Token usage is extracted from the raw API payload before the response body is parsed, so it is always captured regardless of content mode (`json_schema`, `json_mode`, `raw`). Usage is accumulated across all LLM calls in a recognition run — initial crops and correction retries. The `accumulate_usage()` helper correctly skips `None` entries, so a missing usage from one crop does not zero the total. `estimate_cost()` returns `None` for unknown models rather than erroring. `file_size_bytes` is `len(image_bytes)` which is always available.

### 2. Simplicity

**Result:** pass

`TokenUsage` and `RecognitionResult` are plain Pydantic models. `accumulate_usage()` is 8 lines. `extract_openai_usage()` and `extract_anthropic_usage()` are each under 10 lines. `estimate_cost()` is 4 lines. Artifact store additions are straightforward dict mutations. No new abstractions, protocols, or generics were introduced.

### 3. No Scope Creep

**Result:** pass

Only the planned files were modified. The API response schema (`RecognitionResponse`) is unchanged. No new configuration settings, no UI changes, no iOS changes.

### 4. Tests

**Result:** pass

New `test_pricing.py` covers: known model arithmetic, output-only pricing, combined input+output, unknown model returns `None`, `None` model returns `None`, all known models produce valid costs, zero tokens produce zero cost.

`TestAccumulateUsage` covers: summing multiple usages, all-`None` returns `None`, mixed `None`/value, empty list.

`TestExtractOpenAIUsage` and `TestExtractAnthropicUsage` each cover: valid payload, missing key, non-dict value, missing subfields.

Provider tests assert `isinstance(result, RecognitionResult)` and check `result.usage.input_tokens` against known fixture values. `test_recognition_upload_saves_artifacts` asserts `file_size_bytes`, `usage.*`, and absence of `estimated_cost_usd` (mock model has no price entry). All tests would fail if the corresponding implementation were removed.

### 5. Safety

**Result:** pass

No unhandled exceptions. All usage extraction returns `None` for missing or malformed data. `estimate_cost()` receives `None`-guarded calls in both route handlers. No secrets in code. Thread safety: usage extraction is pure (no shared state); accumulation happens after the concurrent crop phase completes.

### 6. API Contract

**Result:** pass

`RecognitionResponse` is unchanged. The 5-tuple is internal to the backend service layer — the route handler still returns `RecognitionResponse`. Schema examples and mock provider behavior are aligned.

### 7. Artifacts and Observability

**Result:** pass

`metadata.json` now contains richer data. No existing fields were removed or renamed. Recognition and detection artifact production is unaffected.

### 8. Static Analysis

**Result:** pass

`make api-lint` reports `Success: no issues found in 22 source files`. One `no-redef` mypy error was encountered during development (duplicate `correction_usage` variable in same scope across two branches) and was resolved structurally by renaming the variable in the single-card branch — no suppressions added.

## Verification Results

```
$ make api-test
...
================== 2 failed, 174 passed, 4 warnings in 12.64s ==================
```

174 passing (up from 155 before this feature). The 2 failures are pre-existing (`test_get_openai_provider` and `test_recognition_can_use_openai_provider_without_live_access`) — both caused by a local `.env` model override (`gpt-5.4-mini`) that overrides the test-specified model. Unrelated to this feature.

```
$ make api-lint
Running mypy...
Success: no issues found in 22 source files
mypy passed.
```

## Notes

The `estimated_cost_usd` field is `null` for the mock provider because the mock model name is `null`, which is not in the pricing dict. For real provider runs, it will be a float rounded to 6 decimal places (e.g., `0.001240`).

Moonshot pricing (`kimi-k2.5`) is now sourced from [pydantic/genai-prices](https://github.com/pydantic/genai-prices) ($0.60/$3.00 per 1M tokens), verified correct as of 2026-04-10. The earlier placeholder value ($1.00/$4.00) has been replaced.

## Addendum 2026-04-10: Pricing refresh review

**What was delivered:**

- `services/api/data/pricing/model_prices.json` — checked-in JSON covering 86 models across openai, anthropic, moonshotai. Refreshed automatically by the make command or the background loop.
- `pricing_refresh.py` — provider-level allowlist (`PROVIDER_ALLOWLIST`), three upstream price-shape handlers (plain, tiered dict, list-of-schedules), atomic write.
- `pricing_loop.py` — async background task; refreshes on startup then every N hours. Survives transient failures.
- `admin.py` route — `POST /api/v1/admin/pricing/refresh`; token-gated; not mounted when no token is configured.
- `scripts/update_llm_pricing.py` — CLI wrapper with `--provider` and `--output` flags.
- `pricing.py` rewritten — `load_prices()` with mtime-aware cache replaces hardcoded `MODEL_PRICES` dict. `estimate_cost()` signature unchanged.
- 25 new tests across 4 new test files.

**Code review checklist for addendum:**

1. **Correctness** — pass. Provider-level allowlist means new upstream models are captured automatically. Tiered and list price shapes both resolve to the base/unconstrained rate. mtime cache invalidates on any write. Admin token compared with `hmac.compare_digest`. Atomic writes prevent partial reads.

2. **Simplicity** — pass. `extract_prices()` is 25 lines. Two small private helpers for price-shape resolution. No new abstractions beyond what the task required.

3. **No scope creep** — pass. Only the files listed in the addendum plan were modified. `estimate_cost()` signature unchanged; no API contract changes.

4. **Tests** — pass. `TestExtractPricesTieredShapes` covers both new price shapes. `TestPricingRefreshLoop` verifies the loop runs immediately, survives failure, and cancels cleanly. Admin tests cover auth, 502 sanitization, and missing-router (404) cases.

5. **Safety** — pass. No unhandled exceptions in service code. Admin token never logged. Upstream error detail not leaked in 502 response. Atomic file writes throughout.

6. **Static analysis** — pass. `make api-lint`: `Success: no issues found in 25 source files`.

**Verification results (post-addendum):**

```
$ make api-update-pricing
Updated 86 model(s) at 2026-04-10T22:19:36.962585+00:00

$ make api-test
2 failed, 208 passed   # same 2 pre-existing .env failures, unrelated to this feature

$ make api-lint
Success: no issues found in 25 source files
```
