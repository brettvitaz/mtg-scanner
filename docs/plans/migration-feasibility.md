# Phase 1 — Serverless iOS feasibility

Measured October 7, 2026. **Native catalog and price installation are feasible; direct OpenAI recognition works. The complete provider and App Store release gates are not yet satisfied.** The Python server still serves normal app scanning. This increment adds an opt-in diagnostic runner, not a production migration.

## Branch integration workflow

All migration increments integrate into **`ios-serverless-migration`** before main.
This feature branch starts from `origin/main` and is independent of Claude's
`standalone-ios` working branch. Create migration task worktrees from
`origin/ios-serverless-migration` and target their PRs at `ios-serverless-migration`.
This user-requested migration base overrides the generic `origin/main` worktree
base for these tasks. Retain worktrees and review artifacts until cleanup is
explicitly requested. Only the completed, verified feature branch will target
`main`; individual migration PRs must target the feature branch.

Existing CI runs on pushes and PRs targeting `ios-serverless-migration` as well
as `main`, with jobs and permissions unchanged. The repository default branch
remains `main`. Claude's working branch and its changes are outside this workflow.

## Acceptance and results

| Gate | Result | Evidence |
| --- | --- | --- |
| Direct OpenAI recognition, full image plus corner crop | Pass | Four real samples, schema responses, 2.24–3.87 seconds per call |
| Direct Moonshot recognition | Fail | Four HTTP 404 responses with configured `kimi-k2.5`; authenticated model listing omitted that model |
| Direct Anthropic recognition | Fail | Four HTTP 400 responses with `claude-sonnet-4-6`; model listing includes it, cause unresolved |
| One constrained correction | Pass, limited | Seeded invalid edition; OpenAI selected one of 13 catalog printings in 2.87 seconds |
| Token counts and cost evidence | Partial | Correction: 4,379 input + 187 output = 4,566 tokens; estimated $0.004126. Initial calls lost usage through a decoder bug; fixed and regression tested |
| Direct MTGJSON download and checksum | Pass | Upstream `AllPrintings.sqlite.gz`, SHA-256 verified, release `5.3.0+20261007` |
| Catalog installation under 300 seconds after download | Pass | 8.48 seconds including checksum-verified gzip decompression and SQLite projection; download 10.25 seconds separately |
| Peak app memory under 250 MB | Pass on this device | Final catalog run: 166,641,664 bytes peak resident; 153,290,616 bytes physical footprint at import completion |
| Catalog equivalence with Python | Pass | 110,453 cards, 873 sets, 711 face names; all stored fields compared, no semantic differences |
| Direct Card Kingdom access/import | Pass technically | HTTP success, 152,264 rows; download 0.59 seconds, import 4.91 seconds |
| Price equivalence with Python | Pass | All 152,264 rows compared against Python import of the exact downloaded JSON |
| Corruption/cancellation retains active database | Pass | Fixture tests plus actual iPhone task cancellation at checkpoint 1,000; active catalog SHA-256 unchanged |
| Provider authorization for public BYOK distribution | Unverified | Successful authenticated requests do not establish distribution permission |
| CK price redistribution/commercial use permission | Unverified | Feed access establishes technical access only |
| App Store release readiness | Unverified | Requires production key handling, consent, terms review and release validation in later increments |

Performance is a measurement from a wired iPhone 17 Pro, iOS 27.0.1, Xcode 27 Debug build. It is not a guarantee on older devices. XCTest covers iOS 18.6 Simulator; there is no physical iOS 18 measurement. The app remained foreground with its idle timer temporarily disabled. Background install/resume is not implemented.

Peak logical files observed in the diagnostic folder during replacement: **1,153,564,574 bytes (~1.15 GB)**. This includes old/new catalog and upstream archives plus price files. It excludes OS/download caches, SQLite temporary files outside that folder and disk allocation overhead; reserve at least 2 GB for a production installer and measure free space before installing. Production cleanup/backup exclusion and low-disk UI belong to the next increment.

The first two runs exceeded memory limits. Foundation file reads retained autoreleased checksum buffers over the long import task. Per-chunk autorelease pools reduced the final measured peak below the limit. Row-wise catalog and price processing also uses bounded buffers. The report records operation success separately from `performanceGate`.

## Recognition evidence and limits

The four repository samples are `4ed-154.jpg`, `the-list_pca-050.jpg`, the existing Wear // Tear crop, and the existing Kruphix crop. The runner supplies the canonical prompt/schema and bottom-left corner JPEG. Output preserves foil evidence, foil type, List evidence, border/copyright/promo text, uncertainty notes and confidence. Eight request-body fixtures were generated from existing Python adapters and compare structured, JSON and raw modes where supported.

These are schema/transport probes, not a recognition accuracy benchmark. The foil sample has visual evidence but no established foil ground truth. The correction selected a valid catalog candidate (`Plague Rats`, `3ED`, `123`); the sample filename indicates a different printing, so validity is **not proof of correct edition identification**. Full validation, confidence policy, enrichment, batch behavior and review UI remain production migration work.

Only one initial request per sample/provider was made, followed by one OpenAI correction request. No automatic live retry or model substitution occurred. Non-billable model-list GETs helped diagnose configuration. No further provider requests are needed to reproduce fixture checks.

The usage decoder originally assumed every usage field was an integer. OpenAI nested token-detail objects broke that assumption. The fix extracts counts individually; realistic nested usage has a failing-then-passing regression. Initial usage cannot be reconstructed from the sanitized reports. Cost is an estimate using the repository's April 29 pricing snapshot; cached-token discounts and current invoices are not verified.

## Design for the following increments

Keep recognition, catalog queries, validation/enrichment, and price lookup as independent Swift services behind the existing view models. Preserve the current recognition response contract while replacing the transport with a local orchestrator. The diagnostic services demonstrate primitives; they are not ready-made production services.

Use SQLite for large catalogs. Install directly from upstream compressed SQLite, verify the archive, project only needed fields into a separate staging database, validate it, close it, and atomically rename it into place. Keep the last working database until successful activation. Treat finishes and color identity as unordered lists for parity; their upstream SQLite order differs from JSON's order.

Use a streaming CK importer with the same ID-first/cheapest-name fallback and foil distinction as Python. A missing price remains missing; a genuine zero remains zero. Expand relative purchase links exactly as the current API does. Activation follows the same staged database approach.

For BYOK recognition, use ephemeral URLSession requests to fixed HTTPS provider endpoints, explicit timeouts/cancellation, and no automatic retry. Reject authenticated redirects and export sanitized errors. Production keys should use Keychain and user-controlled deletion; the Phase 1 environment injection is only for local diagnostics. Add image-sharing consent and clear provider-specific failure states before enabling direct recognition in the app.

Phase 2 can develop the native data foundation with these measured primitives. Do not claim full provider support or release readiness until Moonshot/Anthropic failures and distribution permissions are resolved. Do not delete Python before the later parity and end-to-end migration gates pass.

## Policy evidence

[OpenAI API guidance](https://developers.openai.com/api/reference/overview) advises against exposing keys in client apps. This probe demonstrates user-supplied-key transport; it does not establish an approved public BYOK distribution pattern.

[Anthropic authentication guidance](https://platform.claude.com/docs/en/manage-claude/authentication) documents App Attest for direct iOS access without a proxy. That is a possible alternative authentication design; it is not the BYOK flow tested here and has not been implemented.

[Kimi's documentation](https://platform.kimi.ai/docs/overview) describes its API. Public BYOK distribution authorization remains unverified. Moonshot's configured model also needs replacement and fresh evaluation before claiming compatibility.

[MTGJSON licensing](https://mtgjson.com/license/) covers MTGJSON under MIT; permission for underlying card content, images, trademarks and third-party data must be assessed separately. Card Kingdom commercial feed reuse permission was not established from an authoritative source in this probe.

[Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/) include consent requirements for sharing personal data with third-party AI (5.1.2) and authorization for third-party service content (5.2.2). These are release requirements to design for, not an App Store approval prediction.

## Reproduce and inspect

Run from the retained worktree. Backend dependencies are needed only by host helpers/reference comparisons; device code does not call Python. No API data download/bootstrap is needed for fixture checks after local dependencies exist.

```bash
make ios-build
make ios-lint
make ios-test
make api-test
make api-lint
```

For a connected developer-enabled iPhone, set `DEVICE_ID` to its UDID and use your own signing team when required. Build the **isolated bundle ID** to protect the installed app's data:

```bash
xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner \
  -configuration Debug -destination "id=$DEVICE_ID" \
  -derivedDataPath tmp/device-build \
  PRODUCT_BUNDLE_IDENTIFIER=com.brettvitaz.mtgscanner.feasibility \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device "$DEVICE_ID" \
  tmp/device-build/Build/Products/Debug-iphoneos/MTGScanner.app
make api-bootstrap
.venv/bin/python scripts/phase1-probe.py prepare --env-file /path/to/local/.env
xcrun devicectl device copy to --device "$DEVICE_ID" \
  --source tmp/phase1-inputs --destination Documents/phase1 \
  --domain-type appDataContainer \
  --domain-identifier com.brettvitaz.mtgscanner.feasibility
.venv/bin/python scripts/phase1-probe.py launch --device "$DEVICE_ID" \
  --env-file /path/to/local/.env --probes catalog prices
```

`prepare` writes credential-free prompts, schema, images, pricing and model config. `launch` forwards keys through the devicectl child process environment, never files or command-line JSON. Use `--probes recognition` only when deliberately authorizing the 12 hosted initial calls. Provider model defaults can be overridden through `OPENAI_MODEL`, `MOONSHOT_MODEL`, `ANTHROPIC_MODEL` during preparation. Endpoint overrides in `.env` are not used by this fixed-endpoint diagnostic.

A correction run needs `Documents/phase1/correction-card.json`, a canonical `{ "cards": [...] }` output with the ordinary sample's edition deliberately set to `INVALID`; then launch `--probes correction cancel-catalog`. The active catalog and downloaded upstream database must already exist. The helper does not create that input automatically. Copy each report before another launch, because `report.json` is replaced:

```bash
xcrun devicectl device copy from --device "$DEVICE_ID" \
  --source Documents/phase1/report.json --destination tmp/my-device-report.json \
  --domain-type appDataContainer \
  --domain-identifier com.brettvitaz.mtgscanner.feasibility
```

After copying catalog.sqlite, prices.sqlite, and prices.json from the same device run, compare them with a Python catalog of the same MTGJSON release:

```bash
PYTHONPATH=services/api .venv/bin/python scripts/phase1-compare.py \
  --reference-catalog /path/to/same-release/mtgjson.sqlite \
  --native-catalog tmp/device-catalog.sqlite \
  --price-json tmp/device-prices.json --native-prices tmp/device-prices.sqlite \
  --reference-prices tmp/python-prices.sqlite --output tmp/parity-report.json
```

The comparison creates/overwrites only the explicitly selected host price reference; catalog/native inputs are read-only. All catalog fields are checked. Category order is ignored only for finishes/color identity. Price row storage parity and fixture lookup behavior are checked separately.

## Retained evidence and verification

Sanitized local artifacts are gitignored under `tmp/`, not committed datasets:

- `device-report-progress.json`: initial provider outcomes and original catalog memory failure.
- `device-data-report.json`: successful CK import and second catalog memory failure.
- `device-final-report.json`: final catalog performance, correction token/cost evidence, actual cancellation.
- `parity-report.json`: full catalog, sets, faces and prices comparison.
- `device-catalog.sqlite`, `device-prices.sqlite`, `device-prices.json`, upstream snapshot/checksum: comparison inputs.
- `baseline-ios-*.log`, `red-*.log`, `green-*.log`, `final-*.log`: verification history.

Final checks:

| Check | Result |
| --- | --- |
| `make ios-build` | Pass, Debug simulator build |
| `make ios-lint` | Pass, 0 violations in 202 files |
| `make ios-test` | Pass, 595 tests, 0 failures on iOS 18.6 Simulator |
| `make api-test` | Pass, 243 tests; existing Starlette deprecation warning |
| `make api-lint` | Pass, mypy on 25 API source files |
| Release simulator build | Pass; diagnostic symbols and launch flag absent from binary |
| Host helper verification | Pass, prepare smoke, Python compilation, full parity, missing-column/duplicate-key rejection |
| Credential scan | Pass, no configured API key values in proposed files |
| `git diff --cached --check` | Pass |
| Independent review | Pass after fixing usage decoder; no remaining critical/important findings |

An intermediate overlapping Xcode test run stalled and was interrupted. The final serial full-suite run completed successfully; no result from the interrupted run is counted as a pass. Device builds emitted the existing interface-orientation warning. No App Store archive, physical older-device run, TestFlight upload or production migration was attempted.

All changed files were reviewed against `.agents/rules/code-review.md`:

| Criterion | Result and basis |
| --- | --- |
| Correctness | Pass: fixture behaviors, final device resource gates and all-row parity verified; live provider failures remain explicit feasibility findings |
| Simplicity | Pass: small diagnostic helpers, streaming buffers, no production abstraction hierarchy |
| No scope creep | Pass: opt-in Debug diagnostics, fixtures, host helpers and migration documentation only |
| Meaningful tests | Pass: 18 new XCTest cases exercise request parity, evidence/usage decoding, malformed data, lookup, cancellation and atomic retention |
| Safety | Pass: no force unwraps, actor-owned imports, staged activation, blocked authenticated redirects and credential-free reports |
| API contract | Pass: existing schema, mocks, normal transport and response behavior unchanged |
| Artifacts and observability | Pass: sanitized reports preserve results/failures, resource measurements and limited cost evidence |
| Static analysis | Pass: SwiftLint and mypy pass; no added suppressions |

No criteria are inapplicable for this change. Release authentication, complete recognition accuracy, all-provider success and production background/low-disk lifecycle remain deferred by the Phase 1 scope, not counted as implemented behavior.
