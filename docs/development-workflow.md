# Development Workflow

## Goals
Keep the repo easy for both humans and coding agents to understand, run, and modify.

## Preferred workflow
1. Read `README.md` and `docs/plan.md`.
2. Check `AGENTS.md` for repo-specific conventions.
3. Make the smallest useful change.
4. Update docs and examples alongside code.
5. Run the smallest verification that proves the change.
6. **Commit after each feature or change.**

## Local development
### Backend
- Python: 3.14 or newer. Local bootstrap and CI use the standard Python 3.14 interpreter.
- Bootstrap: `make api-bootstrap`; rerun after upgrading to recreate an older `.venv`.
- Run server: `make api-run`
- Run tests: `make api-test`
- Run type checking: `make api-lint`. It targets the supported Python 3.14 minimum.
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

## Design workflow

The repository uses the consolidated [Impeccable 4.4.0 skill](../.agents/skills/impeccable/SKILL.md),
vendored from upstream commit `114ea1d3838fca73b253af45f873b9c4f5f213c8`.
The launcher pins engine 0.1.7 and verifies its release checksum on first download.
Use `$impeccable shape <feature>` for planning; the former standalone `$shape` skill
has been removed. Use `$impeccable init` for product context (`teach` remains an alias),
`$impeccable document` to record the existing design system, and `$impeccable <feature>`
for implementation (`craft` is a deprecated alias).

The launcher reads `PRODUCT.md`, `DESIGN.md`, and surface briefs. Confirmed product
context is migrated into `PRODUCT.md`. Legacy visual preferences
remain in `.impeccable.md`; use `document` when the current implementation should
be recorded in `DESIGN.md`, preserving existing product facts and design constraints.
A missing new-format context file does not authorize a redesign or fabricated context.
Use the skill's native iOS references for SwiftUI work.

Local packaging corrections: the engine pin follows the current release, the
asset-producer fallback reference resolves within the skill, and Codex UI metadata
uses the supported short-description length and `$impeccable` prompt syntax.
Upstream helper scripts are vendored; no application code changes are included.

## Agent instructions

`AGENTS.md` is canonical at the repository root, `apps/ios/`, `services/api/`,
and `docs/work-efforts/`. The root is a regular file, with no compatibility
symlink or alternate instruction filename. Read the applicable nested file when
working in its subtree. Shared standards live in `.agents/rules/`, with explicit
routing in root `AGENTS.md`; former Claude glob metadata is removed.

The retired `.claude/` settings, skill aliases, and agent definitions are removed.
Their permissions and hooks are not converted into new Codex permissions or
hooks. The worktree requirement remains in `AGENTS.md`. Historical work-effort
logs can retain former filenames as records of completed work.
