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

- **Pricing staleness**: Prices are pinned at commit time. The comment header in `pricing.py` documents source URLs and the date checked. Unknown/custom models return `None` rather than erroring.
- **Multi-path accumulation**: Usage must be collected from both the crop recognition path and the LLM correction path. The `accumulate_usage()` helper handles `None` entries gracefully so missing usage from one path doesn't zero out the total.
- **mypy scope conflict**: Both the multi-card and single-card branches define a `correction_usage` variable in the same function scope. Resolved by renaming the single-card variable to `single_correction_usage`.
- **Database storage**: Deferred. Artifact files are sufficient for now. If query-able history is needed later, a SQLite table mirroring the `metadata.json` fields would be the natural next step.

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
