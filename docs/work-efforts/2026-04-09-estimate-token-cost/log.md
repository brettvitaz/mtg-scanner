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

### Step 11: Added pricing refresh system (background loop, admin endpoint, make command)

**Status:** done

Added `pricing_refresh.py` (shared core: `fetch_upstream`, `extract_prices`, `write_prices`, `refresh_prices_from_upstream`), `pricing_loop.py` (async background task), `admin.py` route (`POST /admin/pricing/refresh`, token-gated via `hmac.compare_digest`), and `scripts/update_llm_pricing.py` (CLI wrapper). Rewrote `pricing.py` to load from `services/api/data/pricing/model_prices.json` with mtime-aware caching instead of a hardcoded dict. Added `mtg_scanner_pricing_refresh_interval_hours` and `mtg_scanner_admin_token` settings. Wired startup/shutdown lifecycle in `main.py`. Committed the checked-in fallback JSON with corrected Kimi pricing ($0.60/$3.00 — sourced from pydantic/genai-prices, verified against upstream).

Added: `test_pricing_refresh.py` (13 tests), `test_pricing_loop.py` (3 tests), `test_admin_pricing.py` (6 tests), `test_startup_pricing_refresh.py` (3 tests). Updated `test_pricing.py` with `TestLoadPrices` class (mtime cache, missing file, malformed file). `make api-test`: 208 passing, same 2 pre-existing failures. `make api-lint`: clean.

Deviations from plan: `claude-haiku-3-5` was dropped from the initial allowlist — it does not exist upstream (the correct upstream id is `claude-3-5-haiku-latest`). The refresh system automatically logged it as missing during the first `make api-update-pricing` run, which caught the error.

---

### Step 12: Switched to provider-level allowlist; expanded model coverage to 86 models

**Status:** done

Replaced `MODEL_ALLOWLIST` (a dict of 8 specific model ids) with `PROVIDER_ALLOWLIST = frozenset({"openai", "anthropic", "moonshotai"})`. `extract_prices()` now pulls every model from allowlisted providers automatically. New model releases (e.g., gpt-5, claude-4, future kimi releases) are picked up on the next daily refresh with no code change.

Extended `extract_prices()` to handle two additional upstream price shapes found in practice: tiered dicts `{"base": N, "tiers": [...]}` (uses base price) and list-of-price-schedules (prefers the entry without a `constraint` key). Added `_resolve_price()` and `_resolve_prices_dict()` helpers. Models without `input_mtok`/`output_mtok` (embeddings, TTS, image, realtime) are skipped silently.

Updated `RefreshResult.missing_models` → `missing_providers`, `scripts/update_llm_pricing.py` `--model` flag → `--provider`. Regenerated `model_prices.json`: 86 models across openai, anthropic, moonshotai.

Added `TestExtractPricesTieredShapes` with 2 tests covering tiered dict and list-of-schedules shapes. `make api-test`: 210 passing (added 2 new tests), same 2 pre-existing failures. `make api-lint`: clean.

Deviations from plan: none

---
