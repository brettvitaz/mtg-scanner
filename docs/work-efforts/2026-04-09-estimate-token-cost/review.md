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

The `estimated_cost_usd` field is `null` for the mock provider because the mock model name is `null`, which is not in `MODEL_PRICES`. For real provider runs, it will be a float rounded to 6 decimal places (e.g., `0.001240`).

Moonshot pricing (`kimi-k2.5`) was not reachable by automated fetch and is a placeholder estimate (`1.00`/`4.00` per 1M tokens). Verify against `https://platform.moonshot.cn/docs/pricing` before relying on Moonshot cost figures.
