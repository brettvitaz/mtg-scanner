# mtg-scanner

Monorepo for an iPhone-first Magic: The Gathering card scanning system.

## Goals
- Capture one or more MTG cards from iPhone
- Upload photos to a backend recognition service
- Return structured card metadata with confidence
- Support human review/correction for uncertain recognitions
- Build an evaluation loop that improves recognition quality over time

## Repository layout
- `apps/ios/` — SwiftUI app and runnable Xcode project
- `services/api/` — FastAPI backend scaffold
- `packages/schemas/` — versioned JSON schemas and example payloads
- `docs/` — architecture, plan, workflow, and decision records
- `prompts/` — AI extraction prompts and variants
- `samples/` — sample images and fixtures
- `evals/` — evaluation cases and results
- `scripts/` — explicit local bootstrap/run/test helpers

## Quick start
### API
The API requires Python 3.14 or newer. Bootstrap selects the standard Python 3.14
interpreter and recreates the local virtual environment. After upgrading, rerun:

```bash
make api-bootstrap
make api-import-ck-prices
make api-update-mtgjson
make api-run
```

### iOS
```bash
open apps/ios/MTGScanner.xcworkspace
```
Run the `MTGScanner` scheme in Xcode. The app flow is:
1. Capture an image with the camera (live detection overlays) or pick from the photo library
2. On-device card detection and perspective-corrected cropping
3. Upload crops to the backend batch endpoint (or full image as fallback)
4. View results list with card thumbnails; tap a card for full detail view with metadata, edition picker, and purchase links

In Auto Scan, **Start** watches for card arrivals and **Stop** resets detection and calibration.
After restarting, move or place the next card to trigger automatic capture. Use the shutter
button to capture a stationary card immediately; it also works while Auto Scan is stopped
without starting automatic scanning. During the settling delay, the shutter captures immediately.
Capture is disabled while a photo is being captured or prepared for recognition. If on-device
cropping finds no card, the original photo is uploaded for recognition.

Auto Scan automatically selects a fixed autofocus-capable ultra-wide camera when the
device supports the 1080p video/photo pipeline. This keeps growing stacks in scanning
stands within closer focusing range without a camera setting or lens switches during scanning.
Phones without a suitable close-up lens use the main camera and may need a lower stack limit.
Normal Scan uses the standard camera. Changing scan mode resets zoom and calibration.

Continuous autofocus targets the detected card during the existing settling delay. Capture
reuses that focus instead of starting another focus/exposure pass at the shutter. If the
lens is still adjusting, an additional wait is limited to 0.5 seconds; the shutter then
fires with continuous autofocus active. Exposure adjustment does not block capture. Photo resolution and quality prioritization are unchanged.

Successful capture does not establish that focus settled or that the image is sharp.
For physical testing, connect the iPhone to macOS Console and filter the app's logs by
subsystem `com.mtgscanner`, category `CameraFocus`. Each shutter request that reaches
capture logs either `Focus settled` or `Focus deadline fallback`, with capture number,
wait duration, target age, lens/position, and separate focus/exposure adjustment flags.
Configuration failures log the underlying error and show a retry message in the app;
retrying an unchanged target attempts configuration again when no prepared state exists.
See [ADR 0007](docs/decisions/adr-0007-auto-scan-focus-and-close-up-camera.md#physical-acceptance-check)
for the physical acceptance check.

## Useful commands
```bash
make bootstrap     # prepare local dependencies
make api-run       # run FastAPI dev server
make api-test      # run backend tests
make tree          # print a compact repo tree
make api-import-ck-prices  # fetch and import Card Kingdom prices
make api-update-mtgjson    # fetch and import MTG json card data
```

## Current status
- SwiftUI iOS app with camera capture, on-device card detection/cropping, batch upload, results list with card thumbnails, and card detail view with metadata, edition picker, and Card Kingdom links
- FastAPI backend with config-driven recognition providers, MTGJSON validation and metadata enrichment, card printings endpoint, Card Kingdom pricing, and local artifact logging
- Versioned JSON schemas with examples and validation tests
- Workflow docs and ADRs for future contributors

See `docs/feature-workflow.md` for the preferred low-token workflow for feature implementation, and `docs/development-workflow.md` for broader repo conventions.

## API routes

### Recognition
- `POST /api/v1/recognitions` — upload a single image for card recognition
- `POST /api/v1/recognitions/batch` — upload multiple pre-cropped card images

Both return a `RecognitionResponse` containing a list of recognized cards. Each card includes identity fields (title, edition, collector number, foil) plus enriched metadata when the card matches the MTGJSON database:

| Field | Description |
|-------|-------------|
| `mana_cost` | Mana cost string (e.g. `{2}{R}`) |
| `set_code` | Three-letter set code (e.g. `M10`) |
| `rarity` | Card rarity (`common`, `uncommon`, `rare`, `mythic`) |
| `type_line` | Full type line (e.g. `Legendary Creature — Human Wizard`) |
| `oracle_text` | Rules text from Oracle |
| `power`, `toughness` | Creature stats |
| `loyalty` | Planeswalker starting loyalty |
| `defense` | Battle defense value |
| `scryfall_id` | Scryfall UUID for the printing |
| `image_url` | Scryfall card image URL (constructed from scryfall_id) |
| `set_symbol_url` | Scryfall set symbol SVG URL |
| `card_kingdom_url` | Card Kingdom purchase link |
| `card_kingdom_foil_url` | Card Kingdom foil purchase link |

Enriched fields are `null` when the card does not match MTGJSON or when the source data lacks the field.

### Card printings
- `GET /api/v1/cards/printings?name=Lightning+Bolt` — returns all printings of a card across all sets

Returns a `CardPrintingsResponse` with a `printings` array. Each printing includes the same enriched metadata fields listed above. Results are sorted by release date (newest first). Returns 404 if no printings are found, 503 if the MTGJSON database is unavailable.

### Card Kingdom pricing
- `GET /api/v1/cards/price?name=Lightning+Bolt&scryfall_id=e3285e6b-...&is_foil=false` — returns Card Kingdom buy/sell prices

Returns a `CardPriceResponse` with `price_retail`, `qty_retail`, `price_buy`, `qty_buying`, and `url`. Requires `MTG_SCANNER_ENABLE_CK_PRICES=true` and a populated price database (run `make api-import-ck-prices`).

### Health
- `GET /health` — liveness check

## iOS app

The app provides a full scanning pipeline:
1. **Scan** — capture with camera (live detection overlays) or pick from photo library
2. **Results list** — card thumbnails with title, set, and collector number
3. **Card detail** — tap a card to see its full details:
   - Card image from Scryfall (tap for fullscreen, toggle to on-device crop image)
   - Edition picker with all printings loaded from the API
   - Mana cost, type line, oracle text, power/toughness or loyalty or defense (with labeled stat badges)
   - Rarity badge, foil toggle, confidence bar
   - Card Kingdom buy/sell prices with stock quantities
   - "Buy on Card Kingdom" button (opens purchase URL)
   - Save correction for manual edits

## Recognition provider config
The backend selects its recognition provider from environment variables.

- Default: `MTG_SCANNER_RECOGNIZER_PROVIDER=mock`
- Real provider: `MTG_SCANNER_RECOGNIZER_PROVIDER=openai`
- Required when using `openai`: `OPENAI_API_KEY`, `MTG_SCANNER_OPENAI_MODEL`
- Optional when using `openai`: `OPENAI_BASE_URL`, `MTG_SCANNER_ARTIFACTS_DIR`, `MTG_SCANNER_OPENAI_RESPONSE_MODE`, `MTG_SCANNER_OPENAI_TIMEOUT_SECONDS`
- General recognition settings: `MTG_SCANNER_ENABLE_MULTI_CARD`, `MTG_SCANNER_MAX_CONCURRENT_RECOGNITIONS`
- Response modes:
  - `json_schema` for OpenAI
  - `json_mode` for OpenAI-compatible JSON mode (for example Ollama)
  - `raw` for prompt-only JSON fallback (for example LM Studio)

## Evaluation harness
- Fixture images go in `samples/fixtures/`
- Expected outputs go in `samples/ground-truth/`
- Run evals with:
  - `PYTHONPATH=services/api python evals/run_eval.py`
- Latest results are written to `evals/results/latest.json`

See [services/api/.env.example](services/api/.env.example) for a concrete backend setup.

### Correcting card identities

Open a card from Results, a collection, or a deck, then tap **Edit**. Use **Change Card** to search by name or **Change Printing** to select another edition. Choose the finish and tap **Save**. **Cancel** or dismissing the sheet discards the draft. Quantity stays unchanged. If the printing and finish already exist in the same collection or deck, confirm **Merge** to combine quantities, or cancel to keep editing. Results allows separate duplicate rows.

### Importing CSV files

CSV imports automatically match printings using supplied set codes, collector numbers,
and Scryfall IDs. A matching set code takes precedence over the edition label, so
vendor names such as “Masterpiece Series: Mythic Edition” and “Mystery Booster/The List”
do not require manual selection. Without a set code, the edition must match the
database's set name or code. Conflicting identifiers and unsupported finishes still
require review.

CSV import has no retry action. If card information cannot be loaded, check the
server connection in Settings, then reopen the import. Ambiguous matches require
choosing a printing or skipping the row.

The import review numbers displayed rows from 1, excluding the CSV header and
blank records. Skipping a row keeps its position in the review list.

### Copying and moving saved cards

Results, collections, decks, card context menus, and saved-card details share a
**Copy/Move** sheet. It defaults to Copy and the full quantity of each selected
row. Adjust each row’s quantity to copy or move part of a stack, then choose an
existing collection/deck or create a new destination. The source collection or
deck is excluded from destinations.

Copy leaves the source unchanged. Move leaves any remaining quantity in the
source and removes fully transferred rows. Matching printings and foil finishes
merge quantities in the destination. Cancel leaves cards and selection unchanged.
Unsaved card details continue to offer Add To.
