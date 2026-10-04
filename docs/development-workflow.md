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

## GitHub pull requests and repository safeguards

The default branch is `main`. Open a pull request from a task branch and use
**Squash and merge**; merge commits and rebase merges are disabled. The squash
commit defaults to the PR title and description, so describe what changed and why.
GitHub automatically deletes the remote task branch after merging. Keep the local
worktree and branch for manual review until cleanup is explicitly requested.

Branch protection applies to administrators as well as collaborators. Pull requests
must pass **Backend tests**, **Backend type checking**, and **Backend security scan**
from GitHub Actions, be up to date with `main`, and resolve all review conversations.
Force pushes, deletion of `main`, and merge commits are blocked. No approving review
is required because the owner must be able to merge their own work; review every
change using `.agents/rules/code-review.md`. Auto-merge is available when all
requirements pass, and GitHub offers the update-branch button for stale PRs.
There is currently no required iOS CI check; run the relevant iOS checks locally.

CI uses read-only contents permissions, immutable action commit SHAs, 15-minute
job timeouts, and cancels superseded runs on the same PR or branch. Repository
settings require full commit SHA pins for actions, default workflow tokens to read
access, and prevent Actions from approving PRs. Dependabot checks Python dependencies
and GitHub Actions weekly; vulnerability alerts and security update PRs are enabled.
Secret scanning and secret push protection are enabled.

For another local checkout still using `master`, update its branch and tracking:

```bash
git branch -m master main
git fetch origin
git branch --set-upstream-to=origin/main main
git remote set-head origin -a
```

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

### Collection and deck quantity operations

Open a collection or deck, then choose **Apply a List** from More options
(or the empty-state button). That list is the preselected **target**, which receives
the changes. Choose or change the target first, then choose a **tool** list supplying
cards and quantities. Every collection/deck pairing is supported.

Choose **Add** or **Subtract**, then **Keep** or **Delete** the tool list on the review
screen. Add sums quantities; Subtract removes only available copies of matching
printings and finishes. Review shortfalls before applying. Keep leaves the tool
unchanged. Delete removes the entire tool, including unmatched cards, in the same
save as the target changes. The target remains even when emptied.

CSV import offers the same Add/Subtract choice, with Add selected initially. Resolve
or skip rows, then choose **Review** to inspect the quantity changes. The file serves
as the tool; no temporary list is created and there is no tool-deletion option.
The supported CSV format is unchanged.

After saving, **Undo** restores the complete operation, including a deleted tool,
until you leave the completion screen. Undo refuses to overwrite subsequent edits
to an affected list’s identities, quantities, or name. Automatic price refreshes do
not block Undo; existing rows keep their latest prices. If the open detail list is
deleted as the tool, closing the action returns to Library. Repeating an action or
CSV import applies its quantities again;
operations are not automatically deduplicated. Printing and foil must match; ambiguous
legacy identities must be corrected before applying.

Simulator fixtures: `make ios-snapshot ROUTE=list-subtract`, `ROUTE=list-operation`,
`ROUTE=list-add-delete`, `ROUTE=list-operation-complete`, and `ROUTE=csv-subtract`.

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

### Card row previews

In Results, collections, and decks, hold a card row to preview a large full-card
image. The successful preview omits repeated collection details. Missing or failed
artwork shows compact card identification; loading uses the same portrait frame.
VoiceOver retains card identity, printing, finish, and artwork status. Tap the
preview to open card detail, or choose Copy/Move, Set as Foil / Set as Non-Foil,
or Delete. Delete retains its confirmation and foil changes retain existing duplicate handling.
Previews are disabled during multiselect. Native menu appearance follows the
installed OS; iOS 18 remains supported.

Use `make ios-snapshot ROUTE=card-row-preview` for the image-only preview fixture.
For sample artwork and missing-data review, launch `card-row-list` (cached
fixture image, no network required). For native menu and gesture review, launch `pricing-results`,
`pricing-collection`, or `pricing-deck` and hold a row. Check light/dark,
large text, horizontal swipes, quantity controls, and preview-to-detail navigation.
