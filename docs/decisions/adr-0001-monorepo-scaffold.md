# ADR-0001: Initial Monorepo Scaffold

## Status
Accepted

## Context
The project needs a simple starting point for an iPhone-first card scanner with a backend recognition service. Early iteration speed and debuggability matter more than production completeness.

## Decision
Use:
- SwiftUI source scaffold for the iOS client under `apps/ios/`
- FastAPI for the backend under `services/api/`
- Versioned JSON schema files under `packages/schemas/`
- Plain scripts and a small Makefile for local workflows

## Consequences
### Positive
- Future contributors can find the main moving parts quickly.
- Contracts and prompts remain explicit and inspectable.
- Local iteration stays lightweight.

### Negative
- The iOS side is intentionally not a fully generated Xcode project yet.
- Some production concerns are deferred until the product loop is validated.
