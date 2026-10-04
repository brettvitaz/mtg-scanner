# Collection deletion row refresh

## Behavior and implementation

Deleting a collection must immediately leave surviving rows displaying their own names,
without leaving the Library tab. Collection and deck labels now use model-backed child
views, which read the name, quantity, and timestamp in their own SwiftUI bodies. This
provides a separate observation boundary for each row. Both lists explicitly use the
existing UUID identity; no model, persistence, navigation, or API contract changes are needed.

Deletion resolves all offsets against a snapshot of the currently filtered models before
mutating the model context. Collections and decks use the same approach.

## Evidence and limits

The precise temporary duplicate-name glitch was **not reproduced**. The original app
showed correct surviving names with the accessibility Delete action on iOS 18.6 and
26.4.1. Device Hub's attempted drag opened the row rather than performing a swipe, so
exact swipe-animation behavior remains unverified. The row observation change addresses
the suspected refresh issue; it is not a confirmed diagnosis of the reported glitch.

The five new regression tests include hosted Library rendering, followed by local Vision
text recognition to assert that each expected name appears once and deleted names are
absent. They cover first/middle/last deletion, renaming, empty states, multi-offset filtered
deletion, and preservation of surviving IDs, names, and card contents. The rendered tests
also pass with the original row code, so they provide behavioral coverage rather than
proof that the original glitch was reproduced.

Manual checks of the changed app on an isolated iOS 26.4.1 simulator verified middle,
last, filtered, and final collection deletions, first/middle/last/filtered/final deck
deletions, correct surviving names, correct collection/deck navigation, and empty states.
First collection deletion is covered by the hosted tests on both runtimes.

## Verification

- Baseline: `make ios-build`, `make ios-lint`, and `make ios-test` passed.
- Final: `make ios-build` passed; `make ios-lint` passed with zero violations.
- Final `make ios-test`: **573 passed, 0 failed**, iOS 18.6.
- Focused `LibraryDeletionTests`: **5 passed, 0 failed**, iOS 26.4.1.
- `git diff --check` passed.
- The first hosted test attempt produced blank images; explicit controller layout and
  appearance setup plus layer rendering corrected the test harness.
- A concurrent build/test attempt hit Xcode's build-database lock. The sequential build
  retry passed. Run builds and tests sequentially when they share DerivedData.

Logs and retained test result bundles are in `tmp/collection-delete-review/` (gitignored).
The reusable disposable SQLite fixture is `tmp/collection-delete-fixture.store`.
The isolated simulator is `Collection Delete Regression`, ID
`14C172C3-BB35-4634-973D-1BE7A67483C8`; it is left available for review.

## Code review checklist

- **Correctness — PASS:** tested surviving names, IDs, contents, deletion targeting,
  renaming, and empty states. Exact reported swipe glitch remains unconfirmed as above.
- **Simplicity — PASS:** small model-backed views and short deletion methods; no new
  production abstractions or dependencies.
- **No scope creep — PASS:** changes are confined to the shared Library deletion and
  row refresh behavior, its regression tests, and this review record.
- **Meaningful tests — PASS:** real SwiftData and hosted SwiftUI paths; deleting no models
  or rendering incorrect names makes the regression assertions fail.
- **Safety — PASS:** UI operations stay on the main actor, no force unwraps or secrets,
  and only disposable isolated simulator fixtures were used.
- **API contract — PASS:** schemas, model fields, and provider behavior are unchanged.
- **Artifacts and observability — N/A:** no recognition/detection behavior changes.
  UI regression screenshots are retained in the test result bundles.
- **Static analysis — PASS:** SwiftLint passes without suppressions.

## Manual review

Worktree: `/Users/brettvitaz/Development/mtg-scanner-worktrees/fix-collection-delete-names`

Branch: `fix-collection-delete-names`. The worktree and review artifacts remain available.

```bash
cd /Users/brettvitaz/Development/mtg-scanner-worktrees/fix-collection-delete-names
git status --short
git diff main...HEAD
make ios-build
make ios-lint
make ios-test
open apps/ios/MTGScanner.xcworkspace
```

To check the interaction manually, create three distinctly named collections,
swipe-delete the first visible row, and immediately verify the two surviving labels and
navigation destinations without switching tabs. Repeat with a search filter and with decks.
