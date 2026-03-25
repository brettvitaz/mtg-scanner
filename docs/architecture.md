# Architecture Overview

## Monorepo Structure

```text
mtg-scanner/
  apps/
    ios/
  services/
    api/
  packages/
    schemas/
  docs/
  prompts/
  samples/
  evals/
  scripts/
```

## High-Level Flow
1. iPhone app captures or selects a photo.
2. App uploads image to backend API.
3. Backend validates request and stores request artifact for debugging.
4. Backend runs recognition pipeline:
   - optional card detection / cropping
   - OCR + vision extraction / LLM structured extraction
   - normalization against MTG card data if needed
5. Backend returns structured JSON response.
6. App shows results and allows manual correction.
7. Sample inputs + outputs can be reused in evals.

## Component Responsibilities

### `apps/ios`
- Camera/photo picker UX
- Upload API client
- Render recognition results
- Correction UI
- Local app state only for MVP

### `services/api`
- Image upload endpoint
- Recognition orchestration and provider selection
- Structured response validation
- Logging/debug artifact capture
- Evaluation support

### `packages/schemas`
- JSON schemas for request/response
- Example payloads
- Versioned contracts used by frontend + backend

### `prompts`
- Prompt templates for AI recognition
- System guidance for conservative foil/set detection
- Variants for testing different extraction strategies

### `samples` / `evals`
- Ground-truth sample inputs
- Expected outputs
- Regression results

## Implementation Biases
- Native iOS over cross-platform for MVP
- Backend-controlled AI integration to keep secrets and experimentation centralized
- Config-driven provider abstraction so mock and real recognition can share one route contract
- Conservative extraction over aggressive guessing
- Human review as a first-class workflow
- Files-on-disk eval loop so agents can inspect failures directly
