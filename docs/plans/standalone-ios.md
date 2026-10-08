# Standalone iOS App — Migration Plan

## Goal

Move all runtime functionality from `services/api/` into the iOS app so it runs
without a server and can be released on the App Store. Decisions are recorded in
`docs/decisions/adr-0008-standalone-ios-app.md`.

## Decisions locked

- Recognition uses the user's own LLM API key (Anthropic native client plus one
  OpenAI-compatible client with presets: OpenAI, Moonshot, DeepSeek, local).
- MTGJSON is built on device from `AllPrintings.sqlite.xz`.
- Card Kingdom prices come from the affiliate `product_catalog.json`, fetched
  directly.
- Updates are version-gated full refreshes (MTGJSON `Meta.json`, Card Kingdom
  `ETag`/`Last-Modified`).
- `services/api` stays as a dev, eval, and parity-reference tool.

## Inventory

| Backend piece | Destination | Phase |
|---|---|---|
| `scripts/update_mtgjson.py`, `mtgjson_index.py` | Swift database builder and catalog queries | 1, 2 |
| `GET /cards/search`, `GET /cards/printings` | Local `CardCatalog` | 2 |
| `scripts/import_ck_prices.py`, `ck_prices.py`, `GET /cards/price` | Local `PriceSource` | 3 |
| `card_validation.py` | Swift matcher and validator | 4 |
| `recognizer.py`, `llm/*_provider.py`, `prompts/card-recognition.md`, `prompts/card-correction.md` | Local `CardRecognizer` with BYO key | 5 |
| `llm/pricing*.py`, `POST /admin/pricing/refresh` | Decide in phase 5: keep token-cost estimate with bundled price table, or drop | 5 |
| `card_detector.py` (OpenCV) | Not ported. `POST /recognitions` uses it to split multi-card images the device did not crop; on-device detection must cover that case | 5 |
| `artifact_store.py` | Not ported (dev artifact). Optional local debug export | — |
| `GET /health` | Removed | 6 |

## Phases

All phases land on one feature branch, which merges to main only when the
migration is complete. Each phase is one or more reviewable commits. A local
implementation replaces the HTTP one only after it matches backend output on the
parity fixtures.

### Phase 0 — Service seam

Extract protocols from `Services/APIClient.swift`: `CardRecognizer`
(`recognizeImage`, `recognizeBatch`), `CardCatalog` (`searchCardNames`,
`fetchPrintings`), and `PriceSource` (`fetchPrice`). `APIClient` becomes the first
implementation. `AppModel`, which views already read from `@Environment`, exposes
`cardRecognizer`, `cardCatalog`, and `priceSource`; it is the one place that picks
the implementation. View models and `RecognitionQueue` take the protocols, not
`AppModel`. The services are not separate environment values because `AppModel`
also uses them (recognition, price refresh) and the HTTP ones depend on its
mutable server URL. No behavior change.

### Phase 1 — On-device card database

- Background `URLSession` download of `AllPrintings.sqlite.xz` with resume.
- Streaming xz decompression to disk (Compression framework, `COMPRESSION_LZMA`).
- `ATTACH` the source and `INSERT … SELECT` into the app schema, mirroring the
  columns and indexes `mtgjson_index.py` uses. Delete the source.
- Free-space check before download; first-launch progress UI; retry on failure.
- `Meta.json` version check on launch (throttled) and background rebuild with
  atomic swap.
- Choose the SQLite access layer (raw `SQLite3` vs. a package such as GRDB) here.

Risks: peak disk use, build time on older devices, app suspension during the
build. Measure on the oldest supported device.

### Phase 2 — Local search and printings

Port the name search and printing lookup from `mtgjson_index.py` and
`routes/cards.py`, including Scryfall image and set-symbol URL construction.
Parity tests from the backend card-route tests.

### Phase 3 — Local Card Kingdom prices

Fetch `product_catalog.json`, upsert into the app database, refresh on
`ETag`/`Last-Modified` change. Port `ck_prices.py` lookup including foil pricing.
Independent of phases 1–2 except for sharing the database.

### Phase 4 — Validation and matching

Port `card_validation.py`: name, set, and collector-number matching, split cards,
and the `needs_correction` status that drives the correction pass. This is the
largest logic port; build parity tests from the pytest validation fixtures first.

### Phase 5 — BYO-key recognition

- Anthropic client and OpenAI-compatible client (`URLSession`, structured JSON
  output matching `packages/schemas/v1/`).
- Settings screen: provider preset, base URL, model, key (Keychain), test-connection.
- Bundle `prompts/` as package resources; keep the files in `prompts/` as the
  source of truth.
- Port the recognizer flow: recognition call, validation (phase 4), LLM correction
  pass with candidate printings.
- Replace the backend's multi-card split of uncropped single images
  (`card_detector.py`) with on-device detection, and decide what happens when the
  device detects no cards.
- Clear error states for missing, invalid, or rate-limited keys. Search, printings,
  and prices remain usable without a key.

### Phase 6 — Remove the HTTP path

Delete `APIClient` recognition/catalog/price calls, the server URL setting, and
health check. Update `README.md`, `docs/project-brief.md`, `docs/plan.md`, and
`AGENTS.md` to describe `services/api` as a dev/eval tool.

### Phase 7 — App Store readiness

Privacy manifest and nutrition labels (images and keys go to the user's chosen
provider), first-launch and no-key onboarding, Wizards Fan Content Policy review
of card names and Scryfall images, app review notes explaining BYO key, TestFlight.

## Ordering

```
0 ──► 1 ──► 2 ──► 4 ──► 5 ──► 6 ──► 7
  └──► 3 ─────────────────┘
```

Phase 3 can run alongside 1–2. LLM client and settings work in phase 5 can start
after phase 0, but end-to-end recognition needs phase 4.

## Verification per phase

- `make ios-build`, `make ios-lint`, `make ios-test`.
- Parity tests against backend fixtures for phases 2–4.
- Phase 1: measured download size, peak disk, build time, and memory on device.
- Phase 5: run `samples/test/` through both backend and on-device recognizers with
  the same provider and compare.
