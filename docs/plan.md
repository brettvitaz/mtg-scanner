# MTG Scanner — Initial Plan

## Product Goal
Build an iPhone-first app that captures one or more Magic: The Gathering cards in a photo, sends the image to a backend recognition service, and returns structured card identifications with confidence and explicit uncertainty handling.

## MVP Scope

### In scope
- iPhone app with camera capture and photo-library fallback
- Upload one image containing one or more cards
- Backend endpoint that accepts image upload
- AI-powered recognition returning structured JSON
- Results screen showing identified cards and confidence
- Manual correction path for uncertain recognitions
- Local evaluation harness using saved sample images

### Out of scope (for MVP)
- Android app
- Direct marketplace listing
- Airtable write integration
- Inventory/price sync automation
- Full account/auth system
- Real-time video scanning

## Functional Requirements
1. User can capture or select a photo containing one or more MTG cards.
2. System returns a list of recognized cards.
3. Each recognized card should attempt to include:
   - title
   - edition / set
   - collector number (if visible)
   - foil flag (only when supported by evidence)
   - confidence
4. System should mark uncertain fields/cards for review rather than over-assert.
5. User can edit/correct returned results.
6. System should preserve original image and response JSON for offline evaluation/debugging.

## Quality Bar
- High confidence on clean single-card photos
- Acceptable performance on multi-card table shots
- Conservative foil detection
- Clear fallbacks when set/collector number cannot be determined
- Structured responses that are easy to test and compare across prompt/model versions

## Architecture Direction
- Frontend: SwiftUI app in `apps/ios`
- Backend: FastAPI service in `services/api`
- Shared contracts: JSON schema and example payloads in `packages/schemas`
- Prompt assets: `prompts/`
- Eval fixtures/results: `samples/` and `evals/`

## Agentic Workflow Principles
- Keep contracts explicit and versioned
- Keep prompts in files, not embedded ad hoc in code
- Save sample failures as eval cases
- Prefer small, composable scripts over hidden tooling
- Make every major component runnable independently
- Use a monorepo so agents can reason across app, API, schemas, and evals in one place

## Phases

### Phase 0 — Foundations ✅
Repo structure, API schema, recognition JSON schema, prompt files, backend skeleton, SwiftUI app skeleton.

### Phase 1 — Recognition Pipeline Proof ✅
Upload endpoint, OpenAI provider integration with config-driven provider abstraction (mock/openai/openai-compatible), structured JSON responses, artifact logging, evaluation harness.

### Phase 2 — iPhone MVP ✅
Camera capture with live card detection overlays, photo picker, upload client, results screen, correction UI scaffold, settings flow.

### Phase 3 — Multi-card Quality Improvements ✅ (partially)
- ✅ Card detection/cropping: YOLOv8n on-device (table mode), VNDetectRectangles + grid interpolation (binder mode), OpenCV server-side
- ✅ On-device perspective-corrected cropping with `CIPerspectiveCorrection`
- ✅ MTGJSON validation for set/title/collector number normalization
- ✅ Batch upload endpoint for multi-card images
- Remaining: crop-first batch scan integration (see `docs/plans/ios-crop-first-batch-scan.md`)
- Remaining: confidence calibration, better foil heuristics

## Resolved Questions
- **AI provider:** OpenAI (gpt-4.1-mini) via structured output. OpenAI-compatible mode supports Ollama and LM Studio.
- **Card boundary detection:** Both on-device (YOLOv8n for table, Vision rectangles for binder) and server-side (OpenCV contour-based).
- **Request model:** Synchronous request/response works for MVP. Batch endpoint handles multi-card images.
- **Metadata for evaluation:** Artifacts store uploaded images, crops, raw recognition output, validation details, and response JSON.
