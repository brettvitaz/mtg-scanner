# Log: Estimate Token Cost

## Progress

### Step 1: Explored codebase and designed plan

**Status:** done

Explored all LLM provider files, `RecognitionService`, `artifact_store.py`, and routes. Confirmed all three providers discard the `usage` field from API responses. Found that `RecognitionService.recognize()` returns a 4-tuple and the artifact store writes `metadata.json` with no usage or file-size fields. Designed the plan before writing code.

Deviations from plan: none

---

### Step 2: Established baseline

**Status:** done

Ran `make api-test`. 155 passing, 2 pre-existing failures (`test_get_openai_provider` and `test_recognition_can_use_openai_provider_without_live_access`) caused by a local `.env` model override — both unrelated to this feature.

Deviations from plan: none

---

### Step 3: Added TokenUsage, RecognitionResult, accumulate_usage

**Status:** done

Added to `models/recognition.py`: `TokenUsage` (input/output/total fields, all `ge=0`), `RecognitionResult` (response + optional usage), and `accumulate_usage()` (returns `None` if all inputs are `None`).

Deviations from plan: none

---

### Step 4: Updated LLMProvider protocol and added extraction helpers

**Status:** done

Changed `LLMProvider.recognize()` return type in `base.py` from `RecognitionResponse` to `RecognitionResult`. Added `extract_openai_usage()` and `extract_anthropic_usage()` — both return `None` gracefully when the `usage` key is absent or not a dict.

Deviations from plan: none

---

### Step 5: Updated all three providers and MockRecognitionProvider

**Status:** done

OpenAI and Moonshot: call `extract_openai_usage(payload)`, wrap result in `RecognitionResult`. Anthropic: call `extract_anthropic_usage(payload)`. `MockRecognitionProvider`: return `RecognitionResult` with synthetic `TokenUsage(1500, 500, 2000)`.

Deviations from plan: none

---

### Step 6: Updated RecognitionService to propagate usage

**Status:** done

`_recognize_multiple_crops()` now returns `list[RecognitionResult]`. `_apply_llm_correction()` return type changed to `tuple[ValidationBatchResult, TokenUsage | None]` — collects usage from correction calls. `recognize()` accumulates all usage via `accumulate_usage()` and adds it as the 5th tuple element.

Encountered a mypy `no-redef` error: both the multi-card and single-card branches defined `correction_usage` in the same function scope. Resolved by renaming the single-card variable to `single_correction_usage`.

Deviations from plan: Variable renamed to resolve mypy scope conflict — no behavioral change.

---

### Step 7: Added pricing module

**Status:** done

Created `services/api/app/services/llm/pricing.py` with `MODEL_PRICES` (8 models across OpenAI, Anthropic, Moonshot) and `estimate_cost(usage, model) -> float | None`. Prices were sourced from provider documentation; the file header records source URLs and the check date (2026-04-10). Unknown models return `None`.

Deviations from plan: none

---

### Step 8: Updated artifact store and route handlers

**Status:** done

`LocalArtifactStore.save_recognition()` gains `usage` and `estimated_cost_usd` optional params. Adds `file_size_bytes`, `usage` dict, and `estimated_cost_usd` (rounded to 6 decimal places) to `metadata_dict` when present. Both route handlers (`/recognitions` and `/recognitions/batch`) unpack the 5-tuple, call `estimate_cost()`, and pass results to the artifact store. The API response is unchanged.

Deviations from plan: none

---

### Step 9: Updated all affected tests and added new tests

**Status:** done

Updated `test_llm_providers.py`: mock HTTP response fixtures now include `usage` fields; assertions check `RecognitionResult` shape and token values. Added `TestAccumulateUsage`, `TestExtractOpenAIUsage`, `TestExtractAnthropicUsage` test classes.

Updated `test_recognitions.py`: two `fake_recognize` functions now return `RecognitionResult`; `test_recognition_upload_saves_artifacts` asserts `file_size_bytes`, `usage.input_tokens`, etc.

Updated `test_card_correction.py`: `fake_recognize` side-effects return `RecognitionResult`; tuple unpackings updated to 5-element.

Updated `test_multi_card.py`: all four `fake_recognize` stubs updated; tuple unpackings updated.

Created `test_pricing.py` with 7 tests covering known models, unknown models, `None` model, all-known-models loop, and zero tokens.

Deviations from plan: none

---

### Step 10: Ran final tests and lint

**Status:** done

`make api-test`: 174 passing, same 2 pre-existing failures. No regressions.
`make api-lint`: `Success: no issues found in 22 source files`.

Deviations from plan: none

---
