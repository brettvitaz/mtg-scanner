# ADR 0008: Standalone iOS app without the hosted API

## Status

Accepted. Implementation is phased in `docs/plans/standalone-ios.md`.

## Context

The iOS app depends on the FastAPI backend in `services/api/` for recognition,
card search, printings, validation, and prices. To ship on the App Store, the app
must run without a server operated by us. Three things block that:

- Recognition calls a hosted LLM with a server-side API key. A key cannot be
  embedded in a shipped app.
- MTGJSON and Card Kingdom data are imported into SQLite by Python scripts and
  served from the backend.
- The backend holds the matching and validation logic (`card_validation.py`,
  `mtgjson_index.py`) that turns LLM output into verified printings.

## Decision

- **Recognition uses the user's own LLM API key.** The app ships two clients: a
  native Anthropic client and one OpenAI-compatible client with a configurable
  base URL and model. Presets cover OpenAI, Moonshot, DeepSeek, and local
  servers (Ollama, LM Studio). Keys are stored in the Keychain and sent only to
  the provider the user configured.
- **The card database is built on device.** The app downloads MTGJSON
  `AllPrintings.sqlite.xz` (~129 MB), decompresses it to disk in chunks with the
  Compression framework, attaches it, and copies only the needed columns into the
  app database with `INSERT … SELECT`. The source file is deleted afterward. No
  JSON parsing and no hosting by us.
- **Updates are version-gated full refreshes.** Neither source publishes deltas.
  MTGJSON is rebuilt when `Meta.json` reports a new version; the Card Kingdom
  catalog is refetched when its `ETag`/`Last-Modified` changes. Rebuilds run in the
  background and swap the database atomically.
- **Prices come from the Card Kingdom affiliate catalog** (`product_catalog.json`),
  fetched directly by the app. This file is published for affiliate use such as
  this app.
- **Logic is ported to Swift, not run remotely.** `services/api` remains as a
  development, evaluation, and parity-reference tool, not a runtime dependency.

## Consequences

The app works without any server we operate, and per-scan LLM cost is paid by the
user. Users must obtain an API key before recognition works, which narrows the
audience; search, printings, and prices work without one.

First launch requires a ~129 MB download plus a few hundred MB of temporary disk
while the database is built. The app must check free space, show progress, and
resume or retry failed downloads. Rebuilds repeat the full download.

Matching and validation logic will exist in both Python and Swift during
migration. Parity tests derived from the pytest fixtures and
`packages/schemas/examples/v1/` keep them aligned until the HTTP path is removed.

On-device recognition without an LLM (Vision OCR plus fuzzy match) was not chosen
for the first release. It remains a possible later fallback for users without a key.
