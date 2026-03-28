# ADR-0003: MTGJSON Validation Design

## Status
Accepted

## Context
AI recognition providers (OpenAI) sometimes return card names, set codes, or collector numbers that don't correspond to real Magic: The Gathering printings. The system needed a way to validate and normalize recognition output against authoritative card data without adding external API dependencies to the request path.

## Decision
Implement a **post-recognition validation layer** using a local SQLite database derived from MTGJSON's `AllPrintings.json`.

### Data pipeline
- An offline importer (`scripts/import_mtgjson.py`) reads `AllPrintings.json` and builds a SQLite database with normalized card/set tables and indexes.
- The database is stored at `services/api/data/mtgjson/mtgjson.sqlite` with a `manifest.json` recording import metadata.
- Refresh is manual/offline — no request-time downloads.

### Matching cascade
For each recognized card, the validator attempts matches in this order:
1. Exact canonical triple (normalized title + set code + collector number)
2. Exact title within resolved set
3. Exact title + collector number across candidate sets
4. Set-name resolution (convert edition text to set code, retry)
5. Normalized title with structured narrowing
6. Conservative fuzzy title match (only when structured fields constrain the search)
7. Ambiguous / no match — preserve original values, lower confidence

### Integration point
Validation runs after the recognizer provider returns results and before response serialization. Each recognized card is validated independently. The public API contract is unchanged — validation canonicalizes field values and adjusts confidence but doesn't add new response fields.

### Confidence policy
- Exact match: keep or slightly boost confidence
- Normalized match: keep approximately current confidence
- Fuzzy match: reduce slightly
- Ambiguous / no match: reduce meaningfully, add explanatory note

Artifact metadata records raw vs. validated values for debugging and evaluation.

## Consequences
### Positive
- Deterministic, reproducible validation with no external dependencies.
- Low latency — SQLite lookups are fast.
- Eval-friendly — artifacts show before/after validation for accuracy analysis.
- Graceful degradation — if the database is missing, recognition still works (unvalidated).

### Negative
- Requires periodic manual refresh of MTGJSON data to cover new sets.
- SQLite database is a build artifact that must be generated before first use.
- Fuzzy matching is intentionally conservative — some valid but misspelled matches may be missed.
