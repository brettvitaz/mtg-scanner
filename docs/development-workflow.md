# Development Workflow

## Goals
Keep the repo easy for both humans and coding agents to understand, run, and modify.

## Preferred workflow
1. Read `README.md` and `docs/plan.md`.
2. Check `CLAUDE.md` for repo-specific conventions.
3. Make the smallest useful change.
4. Update docs and examples alongside code.
5. Run the smallest verification that proves the change.
6. **Commit after each feature or change.**

## Local development
### Backend
- Bootstrap: `make api-bootstrap`
- Run server: `make api-run`
- Run tests: `make api-test`
- Override artifact output with `MTG_SCANNER_ARTIFACTS_DIR=/tmp/mtg-scanner-artifacts` when you want a custom local debug/eval directory.

### iOS
- Start by editing the Swift files under `apps/ios/MTGScannerKit/Sources/MTGScannerKit/`.
- Keep UI state and network logic simple and obvious.
- Avoid introducing package managers or generated project complexity until the app shape stabilizes.

## Contract-first changes
- Update versioned schemas under `packages/schemas/v1/`.
- Add or update matching examples under `packages/schemas/examples/v1/`.
- Keep API mocks aligned with contract examples.

## Agent-friendly rules
- Prefer explicit scripts to hidden task runners.
- Prefer fixture-backed behavior over incomplete external integrations.
- Leave breadcrumbs in READMEs when adding new components.
