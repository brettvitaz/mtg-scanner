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
make api-run
```

### iOS
```bash
open apps/ios/MTGScanner.xcodeproj
```
Run the `MTGScanner` scheme in Xcode. The current MVP flow is:
1. Capture an image with the camera or pick one from the photo library
2. Upload it to the FastAPI backend as multipart form data
3. Save local API artifacts for debugging/evals
4. Display mocked recognition results in the Results tab

## Useful commands
```bash
make bootstrap     # prepare local dependencies
make api-run       # run FastAPI dev server
make api-test      # run backend tests
make tree          # print a compact repo tree
xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build
```

## Current status
This pass establishes a clean MVP foundation:
- Runnable SwiftUI iOS project with camera/photo upload flow
- FastAPI multipart upload endpoint with config-driven recognition providers, mocked output by default, and local artifact logging
- Versioned schema/examples plus validation tests
- Workflow docs and ADRs for future contributors

See `docs/development-workflow.md` for the preferred way to work in this repo.

## Recognition provider config
The backend keeps the current `POST /api/v1/recognitions` contract unchanged and selects its recognition provider from environment variables.

- Default: `MTG_SCANNER_RECOGNIZER_PROVIDER=mock`
- Real provider: `MTG_SCANNER_RECOGNIZER_PROVIDER=openai`
- Required when using `openai`: `OPENAI_API_KEY`, `MTG_SCANNER_OPENAI_MODEL`
- Optional when using `openai`: `OPENAI_BASE_URL`, `MTG_SCANNER_ARTIFACTS_DIR`

See [services/api/.env.example](/Users/brettvitaz/Development/mtg-scanner/services/api/.env.example) for a concrete backend setup.
