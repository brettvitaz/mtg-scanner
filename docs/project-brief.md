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
- Real Xcode project exists at `apps/ios/MTGScanner.xcodeproj`
- SwiftUI app scaffold is in place
- App supports:
  - photo library image selection
  - camera capture
  - upload to backend
  - results display
  - settings flow
- ATS is temporarily permissive for local MVP iteration
- Simulator can use `127.0.0.1`; physical iPhone should point to the Mac’s LAN IP

### Backend
- FastAPI service scaffold exists under `services/api`
- Endpoints include:
  - `GET /health`
  - `POST /api/v1/recognitions`
- Recognition endpoint accepts `multipart/form-data`
- Recognition response is currently **mocked**
- Image content-type validation exists
- Uploaded images and outputs are logged locally for eval/debugging

### Artifact Logging
- Default artifact path:
  - `.artifacts/recognitions/<timestamp>-<id>/`
- Each recognition request currently saves:
  - uploaded image as `upload.<ext>`
  - `response.json`
  - `metadata.json`
- Artifact root can be configured with:
  - `MTG_SCANNER_ARTIFACTS_DIR`

### Shared Contracts / Docs
- Schemas live under `packages/schemas/v1/`
- Example payloads exist for request/response
- Prompt assets live under `prompts/`
- Core docs include:
  - `README.md`
  - `docs/plan.md`
  - `docs/architecture.md`
  - `docs/development-workflow.md`
  - `docs/decisions/adr-0001-monorepo-scaffold.md`

## Implemented MVP Flow
1. Capture or select an image in the iOS app
2. Upload the image to the backend
3. Backend accepts multipart upload and returns mocked recognition data
4. iOS app displays the results
5. Backend stores artifacts locally for debugging/evaluation

## Current Limitations
- Recognition provider integration is not implemented yet
- Recognition output is mocked
- No retention/cleanup policy yet for artifacts
- Camera and scanning UX are still minimal
- No card boundary detection/cropping yet

## Recommended Next Step
Implement a real AI recognition provider behind a provider abstraction while preserving:
- mocked mode for tests/dev
- current response schema
- artifact logging flow
- explicit env-based configuration

## Working Style / Repo Expectations
- Keep docs up to date as architecture and workflow evolve
- Prefer adding explicit scripts/docs over hidden conventions
- Keep prompts in files
- Keep contracts versioned
- Preserve agent-friendly structure and readability
- Use the repo as the primary source of project continuity
