# Handoff: Split Cards Recognized as Two Separate Cards

## Problem

Split cards (e.g., Warrant // Warden) are returned as two separate card entries instead of one. See artifact: `services/.artifacts/recognitions/20260407T063548-add060ac/response.json` — the LLM returned "Marrant" and "Warden" as separate cards, both with `no_match` status and null metadata.

## Root Cause (Multi-layered)

### Layer 1: LLM returns halves separately

The prompt at `prompts/card-recognition.md` has guidance ("ONLY RETURN THE COMBINED CARD NAME WHEN DETECTING A SPLIT CARD") but the LLM still returns halves separately. The guidance is buried in a bullet list and lacks concrete examples. The LLM also misspelled "Warrant" as "Marrant" — likely due to blurry image input.

### Layer 2: No face-name fallback in validation

Even if the LLM correctly returns "Warrant" as a single face name, validation will fail:

- MTGJSON stores full names: `"Warrant // Warden"`
- `normalize_title("Warrant // Warden")` produces `"warrant warden"` (slashes are in `SPACE_PUNCTUATION`, replaced with spaces)
- `normalize_title("Warrant")` produces `"warrant"` — does NOT match `"warrant warden"`
- The entire validation cascade (`lookup_exact` → `lookup_by_name_and_set` → `lookup_by_name_and_number` → `search_candidates` → `lookup_all_printings_by_name`) uses `normalized_name = ?` equality, so a single face name never matches

### Layer 3: No face-name index exists

The MTGJSON import stores only the full card name. There is no table or index mapping individual face names to their parent card. The `faceName` field from MTGJSON data is not captured during import.

## Key Files

| File | Role |
|------|------|
| `services/api/app/services/mtgjson_index.py` | Schema, import, card lookup methods |
| `services/api/app/services/card_validation.py` | Validation cascade (line 92-263) |
| `services/api/app/services/recognizer.py` | Recognition flow, LLM correction loop |
| `prompts/card-recognition.md` | Recognition prompt sent to LLM |
| `services/api/tests/test_mtgjson_index.py` | Index tests with fixture data |
| `services/api/tests/test_card_validation.py` | Validation tests with fixture data |

## Proposed Fix (3 parts)

### Part 1: Add `face_names` table and populate during import

**File:** `services/api/app/services/mtgjson_index.py`

**In `create_schema()` (line 322)**, add after existing table creation:

```sql
DROP TABLE IF EXISTS face_names;
CREATE TABLE face_names (
    face_name TEXT NOT NULL,
    normalized_face_name TEXT NOT NULL,
    full_card_uuid TEXT NOT NULL,
    UNIQUE(normalized_face_name, full_card_uuid)
);
CREATE INDEX idx_face_names ON face_names(normalized_face_name);
```

**In `import_all_printings()` (after line 465)**, for split cards, insert face names:

```python
SPLIT_LAYOUTS = {"split", "aftermath", "fuse"}

# After the main card INSERT, inside the card loop:
card_layout = card.get("layout")
if card_layout in SPLIT_LAYOUTS and " // " in name:
    for face in name.split(" // "):
        face_stripped = face.strip()
        if face_stripped:
            conn.execute(
                "INSERT OR IGNORE INTO face_names "
                "(face_name, normalized_face_name, full_card_uuid) "
                "VALUES (?, ?, ?)",
                (face_stripped, normalize_title(face_stripped), uuid),
            )
```

Define `SPLIT_LAYOUTS` as a module-level constant near the top of the file.

**After schema change, `make api-update-mtgjson` must be re-run** to rebuild the database with the new table.

### Part 2: Add `lookup_by_face_name()` method

**File:** `services/api/app/services/mtgjson_index.py`

Add to `MTGJSONIndex` class (after `lookup_all_printings_by_name` at line 176):

```python
def lookup_by_face_name(self, *, title: str) -> list[CardRecord]:
    """Look up cards where title matches an individual face of a split card."""
    return self._fetch_cards(
        f"""
        SELECT {_CARD_COLUMNS}
        FROM cards
        WHERE uuid IN (
            SELECT full_card_uuid FROM face_names
            WHERE normalized_face_name = ?
        )
        ORDER BY release_date DESC, set_code ASC
        """,
        (normalize_title(title),),
    )
```

### Part 3: Add face-name fallback in validation cascade

**File:** `services/api/app/services/card_validation.py`

In `validate_card()`, after the `lookup_all_printings_by_name` block (line ~255) and before the final `no_match` return (line 257), insert:

```python
# Face-name fallback for split cards
face_matches = self._index.lookup_by_face_name(title=card.title or "")
if len(face_matches) == 1:
    return self._matched(
        card, trace_base, face_matches[0], "corrected_match",
        "Auto-corrected: matched as face name of split card.",
    )
if len(face_matches) > 1:
    return self._needs_correction(
        card, trace_base, face_matches,
        "Title matched as face name of split card in multiple sets.",
    )
```

When `needs_correction` is returned with candidates, the existing LLM correction loop in `recognizer.py` (line 90, `_apply_llm_correction`) will re-send the image with candidates, giving the LLM a chance to pick the correct printing.

### Part 4: Improve the prompt

**File:** `prompts/card-recognition.md`

Add a new section after "Guidance":

```markdown
## Split / Aftermath / Fuse Cards
- Cards divided into two halves (split, aftermath, fuse) are ONE card, not two.
- Return the full combined name with " // " separator: e.g., "Fire // Ice", "Warrant // Warden".
- Do NOT return split card halves as separate entries.
- The collector number is shared by both halves.
```

Add a split card example to the Output Shape section:

```json
{
  "title": "Fire // Ice",
  "edition": "Apocalypse",
  "collector_number": "128",
  "foil": false,
  "confidence": 0.88,
  "notes": "Split card; both halves visible."
}
```

## How the Validation Cascade Works (for context)

`card_validation.py:validate_card()` tries these lookups in order, stopping at first match:

1. **Exact match**: normalized title + set_code + collector_number
2. **Name + set**: normalized title + set_code (1 result → match, >1 → ambiguous)
3. **Name + number cross-set**: normalized title + collector_number across all sets
4. **Search candidates**: normalized name with optional set/number filters
5. **All printings by name**: normalized title across all sets (final fallback)
6. **[NEW] Face-name fallback**: check if title is a face name of a split card
7. **No match**: return raw LLM output with reduced confidence

## Normalization Details

`normalize_title()` (line 272):
- NFKC unicode normalize, lowercase, strip
- Characters in `SPACE_PUNCTUATION` (includes `/`) replaced with space
- Characters in `DROP_PUNCTUATION` (quotes, backticks) removed
- Non-alphanumeric-whitespace replaced with space via regex
- Collapse multiple spaces

Examples:
- `"Fire // Ice"` → `"fire ice"`
- `"Warrant // Warden"` → `"warrant warden"`
- `"Fire"` → `"fire"` (does NOT match `"fire ice"`)
- `"Marrant"` → `"marrant"` (misspelling, won't match anything)

## Tests to Add

### `services/api/tests/test_mtgjson_index.py`

Add split card fixture data to the existing `SAMPLE_MTGJSON` structure:

```python
# Add to an existing set or create a new one:
{
    "uuid": "warrant-warden-war-230",
    "name": "Warrant // Warden",
    "number": "230",
    "layout": "split",
    "language": "English",
}
```

Test cases:
- `test_lookup_by_face_name_finds_split_card` — `lookup_by_face_name(title="Warrant")` returns card with name "Warrant // Warden"
- `test_lookup_by_face_name_finds_second_face` — `lookup_by_face_name(title="Warden")` also works
- `test_lookup_by_face_name_no_match_for_normal_card` — `lookup_by_face_name(title="Lightning Bolt")` returns empty list
- `test_face_names_table_populated` — verify face_names table has rows after import

### `services/api/tests/test_card_validation.py`

Add split card to the existing fixture data and test:
- `test_validate_split_card_face_name_fallback` — card with title "Warrant" gets `corrected_match` status, returned card has name "Warrant // Warden"
- `test_validate_split_card_full_name_still_works` — card with title "Warrant // Warden" still matches via the existing `lookup_all_printings_by_name` path

## Constraints

- Python 3.11+, `str | None` union syntax
- Functions < 30 lines
- All new tests must pass with `make api-test`
- `make api-lint` (mypy) must pass
- `make api-update-mtgjson` must be re-run after schema change
- Do not modify response schema — the fix is purely in validation/lookup
- Existing tests must not break
