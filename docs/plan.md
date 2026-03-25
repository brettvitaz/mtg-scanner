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

## Suggested Phases

### Phase 0 — Foundations
- Create repo structure
- Define API schema
- Define recognition JSON schema
- Add sample prompt file
- Add initial backend skeleton
- Add initial SwiftUI app skeleton

### Phase 1 — Recognition Pipeline Proof
- Build upload endpoint
- Send sample images to chosen AI recognition provider
- Return structured JSON
- Save raw outputs for debugging
- Evaluate accuracy on sample images

### Phase 2 — iPhone MVP
- Camera flow
- Photo picker fallback
- Upload client
- Results screen
- Correction UI

### Phase 3 — Multi-card Quality Improvements
- Card detection/cropping before recognition
- Confidence calibration
- Better set disambiguation
- Better foil heuristics

## Open Questions
- Which AI provider gives best structured extraction quality for MTG cards?
- Should card boundary detection happen on-device, server-side, or both?
- Is synchronous request/response good enough for MVP, or should backend support async jobs for large images?
- What metadata should be persisted for later training/evaluation?
