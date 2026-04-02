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
```bash
make api-bootstrap
make api-import-ck-prices
make api-update-mtgjson
make api-run
```

### iOS
```bash
open apps/ios/MTGScanner.xcodeproj
```
Run the `MTGScanner` scheme in Xcode. The app flow is:
1. Capture an image with the camera (live detection overlays) or pick from the photo library
2. On-device card detection and perspective-corrected cropping
3. Upload crops to the backend batch endpoint (or full image as fallback)
4. View results list with card thumbnails; tap a card for full detail view with metadata, edition picker, and purchase links

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
