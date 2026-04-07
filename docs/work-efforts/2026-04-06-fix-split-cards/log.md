# Log: Fix Blurry Images from iOS Camera

## Progress

Append a new step section each time you complete a meaningful unit of work.
Use the format below. Do not use tables — headings and paragraphs are easier to maintain.

### Step 1: Read handoff and current CameraSessionManager state

**Status:** done

Read `handoff-blurry-images.md` and the current `CameraSessionManager.swift` (lines 1–149). Confirmed: no focus-related code exists anywhere in the file. The `configureOnSessionQueue()` method never calls any focus API, and `capturePhoto()` dispatches capture immediately without a focus-lock step.

Deviations from plan: none

---

### Step 2: Implement configureFocus and refactor capturePhoto

**Status:** done

Added `configureFocus(_ device:)` called from `configureOnSessionQueue()` after `captureDevice = device`. Refactored `capturePhoto()` to enqueue `lockFocusThenCapture()` on the session queue. Added private helpers: `lockFocusThenCapture()`, `captureWithCurrentSettings()`, `restoreContinuousAutoFocus()`. Implementation matches the handoff spec exactly.

Deviations from plan: none

---

### Step 3: Build and test verification

**Status:** done

Ran `make ios-build` → BUILD SUCCEEDED. Ran `make ios-test` → TEST SUCCEEDED (0 failures). No regressions.

Deviations from plan: none

---

## Split Cards Fix

### Step 4: Implement face_names table, lookup_by_face_name, validation fallback, prompt, and tests

**Status:** done

All four parts of the handoff implemented in one pass:

1. `SPLIT_LAYOUTS` constant and `face_names` table added to `mtgjson_index.py`. Face names are populated for `split`, `aftermath`, and `fuse` layouts during `import_all_printings()`.
2. `lookup_by_face_name(*, title: str)` method added to `MTGJSONIndex`.
3. Face-name fallback block added in `card_validation.py:validate_card()` before the final `no_match` return.
4. "Split / Aftermath / Fuse Cards" section and split card example added to `prompts/card-recognition.md`.
5. 4 new tests in `test_mtgjson_index.py`, 2 new tests in `test_card_validation.py`.

Verification: `make api-test` → 146 passed (was 140), same 2 pre-existing failures. `make api-lint` → success.

Note: `make api-update-mtgjson` must be re-run to rebuild the production database with the new `face_names` table.

Deviations from plan: none

---
