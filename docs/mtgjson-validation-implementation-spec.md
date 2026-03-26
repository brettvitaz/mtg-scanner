# MTGJSON Validation Implementation Spec

## Goal
Improve API card recognition quality by validating and normalizing recognizer output against MTGJSON card data.

This work should reduce impossible or hallucinatory card matches, improve confidence in real matches, and help recover correct printings for newer sets by matching on structured card characteristics such as title, set code, set name, and collector number.

## Scope
This feature applies to the backend API in `services/api`.

Primary deliverables:
1. Local MTGJSON-backed validation layer for recognition results
2. Import/index pipeline for MTGJSON data optimized for runtime lookup
3. Request-path integration after recognizer output and before response serialization
4. Tests and eval-oriented validation for exact, normalized, ambiguous, and no-match cases
5. Independent code review sign-off from a separate subagent before merge

## Non-goals
- Do not add request-time dependency on external MTGJSON services
- Do not replace the existing recognizer provider abstraction
- Do not expand the public API contract unless required to complete validation safely
- Do not attempt full support for every MTG card edge case in v1
- Do not make foil determination depend on MTGJSON validation alone

## Product requirements
The implementation should improve these outcomes:
- Recognition results should map to real Magic cards whenever sufficient evidence exists
- Recognition should recover from model uncertainty when title/set/collector fields are close to a real printing
- Newer sets not well represented in the model should still be matchable through MTGJSON metadata
- Ambiguous cases should remain conservative rather than over-correcting to an incorrect printing

## Architectural approach
Implement MTGJSON validation as a **post-recognition normalization and validation stage** inside the API service.

High-level flow:
1. Recognizer provider returns `RecognitionResponse`
2. Validator normalizes each `RecognizedCard`
3. Validator looks up candidate matches in a local MTGJSON-derived index
4. Validator either:
   - confirms the recognizer result
   - corrects it to a canonical MTGJSON printing
   - marks it ambiguous / unverified and lowers confidence
5. API returns the existing response contract
6. Artifact metadata records raw and validated details for debugging and evals

## Why local MTGJSON first
Use local MTGJSON data as the runtime source of truth.

Reasons:
- deterministic behavior
- no external network dependency in the request path
- lower latency and cost
- better fit for eval/replay workflows
- supports recent sets as long as the local dataset is refreshed

MTGGraphQL may be evaluated for future tooling or debugging, but should not be required for request handling.

## Data source
Initial source file provided for development:
- `/Users/brettvitaz/Development/mtg-scanner/tmp/AllPrintings.json`

MTGJSON shape observed:
- top-level keys: `meta`, `data`
- `data` keyed by set code
- each set contains `cards[]`
- card entries contain at least useful fields such as:
  - `name`
  - `setCode`
  - `number`
  - `uuid`
  - `identifiers`
  - `layout`
  - `language`

## Runtime data model
Do not scan `AllPrintings.json` directly in the request path.

Instead, build a derived local index optimized for lookup.

### Recommended runtime format
SQLite database stored under repo-controlled API data path.

Suggested location:
- `services/api/data/mtgjson/mtgjson.sqlite`

### Suggested metadata files
- `services/api/data/mtgjson/manifest.json`

Manifest should include:
- MTGJSON source path or URL
- import timestamp
- MTGJSON version/date if available from source metadata
- total set count
- total card printing count
- importer version or schema version

## Database schema
A minimal schema is sufficient for v1.

### `cards` table
Suggested columns:
- `uuid TEXT PRIMARY KEY`
- `name TEXT NOT NULL`
- `ascii_name TEXT NULL`
- `normalized_name TEXT NOT NULL`
- `set_code TEXT NOT NULL`
- `set_name TEXT NULL`
- `collector_number TEXT NULL`
- `normalized_collector_number TEXT NULL`
- `language TEXT NULL`
- `layout TEXT NULL`
- `release_date TEXT NULL`
- `is_promo INTEGER NULL`

### `sets` table
Suggested columns:
- `set_code TEXT PRIMARY KEY`
- `set_name TEXT NOT NULL`
- `normalized_set_name TEXT NOT NULL`
- `release_date TEXT NULL`

### Indexes
Required indexes:
- `idx_cards_name ON cards(normalized_name)`
- `idx_cards_name_set ON cards(normalized_name, set_code)`
- `idx_cards_name_set_number ON cards(normalized_name, set_code, normalized_collector_number)`
- `idx_cards_set_number ON cards(set_code, normalized_collector_number)`
- `idx_sets_name ON sets(normalized_set_name)`

## Normalization rules
Create shared normalization helpers used by both importer and validator.

### Title normalization
- Unicode normalize
- lowercase
- trim surrounding whitespace
- collapse repeated whitespace
- remove or standardize punctuation differences that commonly vary in OCR/model output
- preserve enough structure to avoid over-merging distinct card names

### Set normalization
- uppercase set codes
- trim whitespace
- normalize set names with similar text normalization rules

### Collector number normalization
- trim whitespace
- lowercase suffix letters if present, or choose one canonical format consistently
- preserve suffixes such as `123a`
- normalize leading zeros carefully without destroying identity
- strip obvious OCR noise only when safe

## Matching algorithm
Prefer exact and deterministic matching before fuzzy matching.

### Inputs from recognizer
Current public fields available from recognizer output:
- `title`
- `edition`
- `collector_number`
- `foil`
- `confidence`
- `notes`

Treat `edition` as possibly either:
- set code
- set name
- noisy recognizer text

### Matching order
For each recognized card, attempt the following in order:

1. **Exact canonical triple match**
   - normalized title + set code + normalized collector number
2. **Exact title within resolved set**
   - normalized title + set code
3. **Exact title + collector number across candidate sets**
4. **Set-name-resolved match**
   - if `edition` maps to a set name, convert to set code then retry
5. **Normalized title match with structured narrowing**
   - normalized title + optional set/collector constraints
6. **Conservative fuzzy title match**
   - only when structured fields narrow the search enough
7. **Ambiguous / no match**
   - preserve original values where necessary and lower confidence

### Matching outcomes
Internal status values:
- `exact_match`
- `normalized_match`
- `fuzzy_match`
- `ambiguous_match`
- `no_match`

These do not need to be added to the public response schema in v1, but must be recorded in artifacts or internal metadata.

## Confidence policy
Returned confidence should reflect both recognizer confidence and validation quality.

Suggested policy:
- `exact_match`: keep current confidence or slightly boost, capped at 1.0
- `normalized_match`: keep approximately current confidence
- `fuzzy_match`: reduce slightly unless confidence was already low
- `ambiguous_match`: reduce meaningfully
- `no_match`: reduce meaningfully and add explanatory note

The public API may continue returning a single `confidence` field. Internal metadata should preserve:
- original model confidence
- validation status
- validation score or reason

## Public API contract
Preserve the existing response contract unless implementation reveals a blocking limitation.

Current response model:
- `title`
- `edition`
- `collector_number`
- `foil`
- `confidence`
- `notes`

### Canonicalization behavior
When validation finds a trusted MTGJSON match, returned values should be canonicalized to MTGJSON values:
- `title` -> canonical card name
- `edition` -> canonical set code or current API-expected edition representation
- `collector_number` -> canonical collector number

If there is ambiguity about whether `edition` should remain set name versus set code, preserve the currently expected semantics in this repo and document the decision in code/tests.

## Artifact logging and observability
Validation behavior must be visible in artifacts for debugging and evals.

Extend artifact metadata to include, per recognized card where practical:
- raw recognizer values
- normalized lookup inputs
- validation status
- matched MTGJSON uuid if matched
- matched set code
- matched collector number
- confidence before validation
- confidence after validation
- human-readable match reason

If changing `metadata.json` structure is awkward, add a new validation block rather than overloading existing fields.

## Proposed code structure
Add these modules:

- `services/api/app/services/mtgjson_index.py`
  - database access
  - exact lookup helpers
  - constrained candidate search
- `services/api/app/services/card_validation.py`
  - normalization helpers
  - validation orchestration
  - confidence adjustment policy
- `scripts/import_mtgjson.py`
  - import `AllPrintings.json`
  - build SQLite db + manifest

Update these modules:
- `services/api/app/settings.py`
- `services/api/app/services/recognizer.py`
- `services/api/app/services/artifact_store.py`
- `services/api/README.md`
- prompt file(s) under `prompts/` if needed

## Suggested service interfaces
These are indicative, not mandatory, but implementation should be similarly explicit.

### MTGJSON index service
- `lookup_exact(title, set_code, collector_number) -> CardMatch | None`
- `lookup_by_name_and_set(title, set_code) -> list[CardMatch]`
- `lookup_by_name_and_number(title, collector_number) -> list[CardMatch]`
- `resolve_set(edition_text) -> set_code | None`
- `search_candidates(title, set_code=None, collector_number=None, limit=10) -> list[CardMatch]`

### Validation service
- `validate_card(card: RecognizedCard) -> ValidatedRecognizedCardResult`
- `validate_response(response: RecognitionResponse) -> RecognitionResponse`

Where `ValidatedRecognizedCardResult` should include:
- validated `RecognizedCard`
- status
- matched uuid if any
- reason
- original values

## Integration plan
### Step 1: importer
Build an importer that reads `AllPrintings.json` and writes:
- SQLite database
- manifest metadata

Importer requirements:
- idempotent rebuild behavior
- clear error handling for malformed source files
- skip or handle incomplete card entries safely
- avoid loading more structure into runtime than necessary

### Step 2: validator service
Build validator logic independent of the recognizer provider.

Validator requirements:
- work with single-card and multi-card recognition flows
- accept partial recognizer output
- avoid hard failures when the MTGJSON database is missing or stale
- fall back gracefully if validation cannot run

### Step 3: request-path integration
Integrate validation after provider recognition in `RecognitionService.recognize()`.

Requirements:
- multi-card flow should validate each recognized card independently
- existing route contract should remain intact
- validation should not break mock provider behavior

### Step 4: prompt tuning
Update recognition prompts so the model emits conservative, validation-friendly fields.

Prompt guidance should encourage:
- printed title when visible
- set code when visible
- collector number when visible
- uncertainty rather than hallucination
- no fabricated set codes or card names

## Configuration
Add environment/config settings for validation.

Suggested settings:
- `MTG_SCANNER_ENABLE_MTG_VALIDATION=true`
- `MTG_SCANNER_MTGJSON_DB_PATH=services/api/data/mtgjson/mtgjson.sqlite`
- `MTG_SCANNER_MTGJSON_SOURCE_PATH=/Users/brettvitaz/Development/mtg-scanner/tmp/AllPrintings.json`
- `MTG_SCANNER_MTGJSON_MAX_FUZZY_CANDIDATES=10`

Optional later settings:
- `MTG_SCANNER_MTGJSON_REFRESH_ENABLED=false`
- `MTG_SCANNER_MTGJSON_REFRESH_URL=<official MTGJSON download URL>`

## Refresh/update workflow
Do not refresh MTGJSON in the request path.

Instead, support an offline/manual refresh flow.

### Phase 1 refresh workflow
- obtain latest MTGJSON source file manually or via explicit script
- run importer to rebuild database and manifest
- commit code/docs, but large generated data should only be committed if repo policy explicitly allows it

### Phase 2 refresh workflow
Add a helper script or make target for monthly refresh.

Possible commands:
- `make mtgjson-import`
- `make mtgjson-refresh`

Document clearly whether generated SQLite artifacts belong in git or are developer-local build products.

## Testing requirements
Testing is required for this feature. Do not claim completion without it.

### Unit tests
Add focused tests for:
- title normalization
- set normalization
- collector number normalization
- exact triple match
- set-name resolution
- ambiguous match handling
- no-match handling
- confidence adjustment logic

Suggested files:
- `services/api/tests/test_mtgjson_index.py`
- `services/api/tests/test_card_validation.py`

### Importer tests
Add tests for:
- importing a minimal synthetic MTGJSON fixture
- expected row counts and indexable values
- malformed/incomplete source handling

### Integration tests
Add API-level tests that verify:
- recognition response is post-processed by validator
- mock provider path still works when validation is enabled
- multi-card detection flow still returns cards and validates each card independently
- missing MTGJSON database fails gracefully according to intended behavior

### Manual validation / eval checks
Run and report the smallest set that proves the feature works:
- backend test suite for changed modules
- one or more sample recognition runs using fixtures if available
- inspect generated artifact metadata for validation details

If sample images or eval fixtures exist, compare:
- recognizer output before validation
- final response after validation

## Review and sign-off requirements
A separate code review subagent must review the implementation before sign-off.

Implementation is not complete until both are true:
1. coding agent reports code + tests completed
2. separate review agent signs off after reviewing the produced diff and verification results

The review agent should explicitly check:
- correctness of matching logic
- conservatism in ambiguous cases
- test coverage quality
- failure behavior when MTGJSON data is unavailable
- maintainability of importer and runtime query logic

## Verification checklist
Minimum required before completion:
- importer runs successfully on provided MTGJSON source
- backend tests covering new logic pass
- integration tests for request-path validation pass
- artifact metadata shows validation details for at least one exercised example
- independent review agent signs off
- changes are committed

## Phased execution plan
### Phase 1: local validation MVP
- importer from `AllPrintings.json` to SQLite
- exact and normalized matching
- request-path integration
- artifact metadata
- tests

### Phase 2: stronger heuristics
- conservative fuzzy title matching
- set-name alias improvements
- better collector-number normalization
- stronger ambiguity handling

### Phase 3: refresh automation
- import/refresh scripts or make targets
- docs for monthly update workflow
- optional scheduled refresh workflow outside request path

### Phase 4: optional contract enrichment
Only if needed later:
- expose validation status
- expose canonical identifiers like MTGJSON uuid
- expose richer match metadata to clients

## Deliverables for subagents
The coding subagent should produce:
- implementation changes
- tests
- docs updates
- verification summary
- commit hash

The review subagent should produce:
- review summary
- required changes if any
- explicit sign-off or rejection

## Constraints
- Keep changes focused on this feature
- Preserve API contract unless explicitly justified
- Prefer deterministic matching over aggressive fuzzy correction
- Do not use ACP threads for this work
- Commit after completing the feature work
