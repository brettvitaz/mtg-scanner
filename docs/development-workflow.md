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
- Transfer interaction tests use ViewInspector, a test-only Swift package dependency, to invoke production SwiftUI controls and check selection handling. Run them with `make ios-test`; the app target does not depend on ViewInspector.
- iPhone uses portrait throughout the app, including scanning, sheets, and fullscreen card artwork. iPad supports portrait and landscape left/right. The orientation policy lives in the app shell’s `Info.plist`; camera sensor buffers and imported images retain their existing orientation handling.
- Avoid introducing package managers or generated project complexity until the app shape stabilizes.

### Repeatable iOS UI workflows

Run `make ios-ui-test` for the offline saved-card finish workflow on iPhone 16 /
iOS 18.6. It opens a saved non-foil card in the production detail screen, edits it
to Foil, saves, checks dismissal, then terminates/relaunches and verifies the saved
finish. No backend, network access, or API keys are required.

```bash
make ios-test
make ios-ui-test IOS_UI_TEST_RESULT_BUNDLE=tmp/card-finish-review.xcresult
open tmp/card-finish-review.xcresult
xcrun xcresulttool export attachments --path tmp/card-finish-review.xcresult --output-path tmp/card-finish-review
```

Use a new result path each time. Without an override, each run retains a unique
`tmp/ios-ui-tests-<timestamp>-<UUID>.xcresult`. A failed workflow returns a nonzero
command status and preserves diagnostics. Named initial, editor, saved, and relaunch
screenshots remain available on success. Inspect those PNGs alongside logic checks;
use existing `card-detail` / `card-edit` snapshot routes for further visual iteration.

Override `IOS_UI_TEST_DESTINATION` with a pinned simulator destination or use
`IOS_UI_TEST_FILTER=MTGScannerUITests/CardFinishTests/testEditFinishPersistsAfterRelaunch`
to select a test. The dedicated scheme is separate from the logic-test scheme.

Each test chooses a UUID. DEBUG launch support creates only that run's disk store
and preferences suite. Fresh mode resets and seeds; resume reopens saved data without
reseeding; teardown cleanup removes only that run. Interrupted tests may leave isolated
resources; later runs get a new UUID. A local URL protocol supplies deterministic
price responses and fails visibly for unexpected requests. See `apps/ios/AGENTS.md`
for exact paths and launch keys.

For interactive changes, agents must run relevant UI workflows alongside logic tests
and inspect screenshots. Add a workflow when existing tests cannot exercise the changed
interaction. Report commands, results, artifacts, and coverage gaps. The initial finish
workflow provides no coverage of other interactions; this foundation adds no CI jobs.

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

## Capture navigation

Leaving Table or Station stops new automatic captures and turns off the torch.
A photo capture already accepted by the camera, cropping, and queued recognition
continue; successful identifications appear in Results. Switching capture tabs resets
zoom/calibration. Returning to Station does
not restart automatic capture. Its explicit Stop/reset still discards an unfinished
capture, and the recognition badge's Cancel action cancels queued uploads.
Zoom changes while watching/settling use a separate pause: thumbnail and queued jobs
remain, settling is cancelled, and Start establishes a fresh motion baseline.

Capture UI changes begin with a native feasibility checkpoint in the production tab
shell: Table/Station, exposed inline zoom, base/half-step taps, threshold crossings,
retarget/pinch interruption, capture locks, brightness, toast, and largest text. Keep
full-screen PNGs, gesture recordings, pinned simulator OS, and a concern-by-concern
verdict. A passing geometry test does not establish native materials or physical focus.
The capture rework checkpoint is recorded in the task worktree's
`tmp/capture-rework-build/checkpoint-report.md`; its first inspection and correction
artifacts remain available for manual review.

Run `make ios-build`, `make ios-lint`, `make ios-test`, and
`make ios-ui-test IOS_UI_TEST_FILTER=MTGScannerUITests/CaptureControlsTests`.
Pin `IOS_TEST_DESTINATION` / `IOS_UI_TEST_DESTINATION` to an installed OS. For iPad,
`CaptureControlsTests/testTabletOrientationKeepsControlsOnTheShutterAxis` covers both
landscape orientations and portrait. Export `XCUIScreen.main.screenshot()` attachments
for full-display landscape evidence; app-only screenshots can crop the rotated canvas.
Named SwiftUI action invocation is currently
unavailable through ViewInspector on the installed runtime; that test reports an
explicit skip. Check those actions and VoiceOver focus continuity on a device.

Use `make ios-snapshot ROUTE=capture-zoom-open` and the capture routes in
`apps/ios/AGENTS.md` for production-shell visual checks. `capture-zoom-menu` is a
compatibility alias for the exposed inline controls. Transition routes hold the
fixture motion driver at an intermediate applied value while the button presents the
chosen destination; selecting a different anchor replaces that held request and completes
normally. The frame fixture proves logic and layout, not optical zoom. Production presets
use the native camera ramp; deterministic fixtures use an elapsed-time
driver. Pinch shows applied factors and caps rounded family labels below their next
threshold. Both modes share a root-owned close-focus camera session and identical fallback.
Ownership checks prevent an outgoing tab from stopping the current session. Preset progress
is output only; SwiftUI updates never feed it back as a new camera request. Hardware configuration and mutation run
on the session queue, with the accepted-photo and Station pause guards checked
before the first mutation. Stop/navigation invalidate queued frames and late callbacks.

For physical acceptance, run the app from `open apps/ios/MTGScanner.xcworkspace`.
In Table, capture a complete nine-pocket binder page and inspect all page/card edges,
titles, and collector numbers in the full-resolution photos and crops. In Station,
follow ADR 0007's physical acceptance check for low/middle/high stacks at the user's
125–175 mm reference distances (geometry, not a guaranteed focus range). Include a
phone using the main-camera fallback when available. Enable Save Raw Captures to
Photos in Debug and inspect Console's `com.mtgscanner` / `CameraFocus` logs.
Simulator snapshots cannot establish these optical or framing results.

## Contract-first changes
- Update versioned schemas under `packages/schemas/v1/`.
- Add or update matching examples under `packages/schemas/examples/v1/`.
- Keep API mocks aligned with contract examples.

## Agent-friendly rules
- Prefer explicit scripts to hidden task runners.
- Prefer fixture-backed behavior over incomplete external integrations.
- Leave breadcrumbs in READMEs when adding new components.

## Design workflow

The repository uses the consolidated [Impeccable 4.5.0 skill](../.agents/skills/impeccable/SKILL.md),
vendored from upstream commit `508d7e8955de3b3caf2d8676e85206723d41a887`.
The launcher pins engine 0.1.11 and verifies its release checksum on first download.
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

The vendored payload comes from the official `skill-v4.5.0` release bundle.
Its SHA-256 is `a6877c158ec90c63560728553d2e737081afa8a79b86c507fa8d15a81fffd475`.
The existing upstream license is retained because the bundle omits it.
Local packaging corrections: Codex UI metadata uses the supported short-description
length and `$impeccable` prompt syntax, and trailing whitespace in upstream Markdown
is removed. The upstream fallback reference now resolves without a local correction.
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

`.pi/settings.json` disables the browser-automation and pi-lens packages for
pi sessions in this repo. Neither applies to iOS or backend work, and together
they added about 15K prompt tokens per session. Verify changes with the `make`
targets in `AGENTS.md` instead. Remove a package entry to restore it.

### Card row previews

In Results, collections, and decks, hold a card row to preview a large full-card
image. The successful preview omits repeated collection details. Missing or failed
artwork shows compact card identification; loading uses the same portrait frame.
VoiceOver retains card identity, printing, finish, and artwork status. Tap the
preview to open card detail, or choose Copy…, Move…, Set as Foil / Set as Non-Foil,
or Delete. Delete retains its confirmation and foil changes retain existing duplicate handling.
Previews are disabled during multiselect. Native menu appearance follows the
installed OS; iOS 18 remains supported.

Use `make ios-snapshot ROUTE=card-row-preview` for the image-only preview fixture.
For sample artwork and missing-data review, launch `card-row-list` (cached
fixture image, no network required). For native menu and gesture review, launch `pricing-results`,
`pricing-collection`, or `pricing-deck` and hold a row. Check light/dark,
large text, horizontal swipes, quantity controls, and preview-to-detail navigation.

Before changing the common camera policy, compare viable physical lenses on the same
phone at equivalent applied factors in both modes, separately recording intentional
1× resets. Keep lens/capability/minimum-focus-distance data, configured photo dimensions,
preview crop/aspect, focus/deadline logs, complete binder pages, low/middle/high Station
stacks, full-resolution crops and fallback-device evidence. The current rework has not
selected a validated common policy; ADR 0007's close-focus evidence must remain intact.
