# Project Brief

## Project
`mtg-scanner` — an iPhone-first Magic: The Gathering card scanning system.

## Goal
Capture one or more MTG cards in a photo, upload the image to a backend recognition service, and return structured card identifications with confidence and explicit human-review-friendly uncertainty handling.

## Repository
- Local path: `~/Development/mtg-scanner`
- Intended to be hosted as its own GitHub repository
- Monorepo layout for coordinated app/backend/schema/eval work

## Stack Decisions
- **Frontend:** SwiftUI
- **Backend:** FastAPI
- **Contracts:** JSON Schema
- **Workflow bias:** optimize for agentic programming, explicit files, clear docs, minimal magic, debuggable local development

## Why SwiftUI
SwiftUI was chosen over React Native because this MVP is camera- and image-pipeline-heavy. Native iOS should provide a cleaner path for image capture quality, permissions, orientation handling, and future on-device vision/cropping work.

## Current State
### iOS
- Real Xcode project at `apps/ios/MTGScanner.xcodeproj`
- SwiftUI app with full scanning pipeline:
  - Camera capture with live card detection overlays (YOLOv8n Core ML model)
  - Photo library image selection
  - On-device card cropping with perspective correction (`CIPerspectiveCorrection`)
  - Batch upload of cropped card images to backend
  - Fallback to single-image upload when no cards detected
  - Results display and settings flow
- Binder mode: detects binder page via `VNDetectRectanglesRequest`, subdivides into 3x3 grid
- Detection stabilized with EMA smoothing and presence hysteresis (`CardTracker`)
- ATS is temporarily permissive for local MVP iteration

### Backend
- FastAPI service under `services/api`
- Endpoints:
  - `GET /health`
  - `POST /api/v1/recognitions` — single image upload
  - `POST /api/v1/recognitions/batch` — multi-image batch upload
- Config-driven recognition providers: mock (default), OpenAI, OpenAI-compatible (Ollama, LM Studio)
- Server-side card detection and cropping (OpenCV-based) for multi-card images
- MTGJSON validation: post-recognition normalization against local SQLite card database
- Parallel per-card recognition with bounded concurrency

### Artifact Logging
- Default artifact path: `.artifacts/recognitions/<timestamp>-<id>/`
- Each recognition request saves: uploaded image, crops, `response.json`, `metadata.json` (including validation details)
- Artifact root configurable with `MTG_SCANNER_ARTIFACTS_DIR`

### Shared Contracts / Docs
- Schemas live under `packages/schemas/v1/`
- Example payloads exist for request/response
- Prompt assets live under `prompts/`
- Core docs include:
  - `README.md`
  - `docs/plan.md`
  - `docs/development-workflow.md`
  - `docs/decisions/` — architecture decision records

## Implemented Flow
1. Capture image with camera (live card detection overlays guide framing) or select from photo library
2. On-device card detection and perspective-corrected cropping
3. Upload cropped card images to backend batch endpoint (or full image to single endpoint as fallback)
4. Backend performs optional second-pass detection/cropping, then per-card AI recognition (OpenAI)
5. Backend validates recognition output against MTGJSON card database
6. iOS app displays recognized cards with confidence
7. Backend stores artifacts locally for debugging/evaluation

## Current Limitations
- No crop editing UI — user cannot adjust detected crop regions before upload
- Crop-first batch scan flow not yet integrated end-to-end (see `docs/plans/ios-crop-first-batch-scan.md`)
- No retention/cleanup policy for artifacts
- Camera and scanning UX are functional but minimal
- No account/auth system
- Correction UI exists but needs refinement

## Recommended Next Step
Implement the crop-first batch scan flow described in `docs/plans/ios-crop-first-batch-scan.md`:
- On-device crop preview before capture
- First-pass crops uploaded to batch endpoint
- Backend second-pass crop tightening before recognition

## Working Style / Repo Expectations
- Keep docs up to date as architecture and workflow evolve
- Prefer adding explicit scripts/docs over hidden conventions
- Keep prompts in files
- Keep contracts versioned
- Preserve agent-friendly structure and readability
- Use the repo as the primary source of project continuity
