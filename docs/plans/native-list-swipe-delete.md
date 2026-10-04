# Native swipe deletion across card lists and Library

## Behavior

Results, Collection detail, Deck detail, and Library's collection/deck rows use
SwiftUI's native trailing swipe actions. A partial swipe reveals a destructive
Delete button with a trash icon; a full swipe invokes the same deletion callback.
The system owns snapping, reveal geometry, gesture arbitration, and animation.
Delete styling matches across these screens within each supported iOS version.

Card rows retain a native blue leading foil action with a current-state label and
full-swipe support. Selection mode has no swipe actions. Card deletion keeps its
existing Undo path; Library deletion retains its existing semantics. Library row
layout, headers, rename, navigation, and context menus are unchanged.

The custom card-row gesture rendered noninteractive action backgrounds and
ignored final translation on release. Its state, thresholds, offsets, animation
callbacks, and open-row coordination are removed. The exact trigger of the
intermittent partially exposed row was not reproduced before replacement.
Native actions sit outside the UIKit context-menu host so the containing List
owns them. Library actions capture their target object rather than filtered-list
indices; obsolete offset helpers and custom-state tests are removed.

## Verification — 2026-10-04

- Remote main fetched and matched local main before worktree creation.
- Baseline: app build, strict SwiftLint, and complete iOS 18.6 suite passed.
  An initial test launch overlapped the build and hit Xcode's build-database lock;
  running sequentially resolved it before implementation.
- Final: `make ios-build`, `make ios-lint`, and complete iOS 18.6 suite passed
  (577 tests, zero failures/skips).
- iOS 26.4.1: LibraryDeletionTests, CardRowContextMenuTests, AppModelUndoTests,
  and CollectionItemFoilToggleTests passed (30 tests, zero failures/skips).
  The OS=26.4 destination did not match the installed 26.4.1 simulator; the
  rerun used its exact ID.
- Device Hub/iPhone 17: native partial reveal, tapping Delete on Counterspell,
  quantity/totals update, and toolbar Undo restoring normal row presentation
  were observed on iOS 26.4.1.
- Device Hub/iPhone 16: collection and deck accessibility Delete actions removed
  the intended fixture objects and updated section counts/empty states. This
  validates the callbacks, not swipe gesture delivery.
- iPad Pro 13-inch: collection list inspected in light mode and dark mode with
  accessibility-extra-large text. Original appearance/text-size settings restored.
- iPad Deck detail: accessibility foil toggle updated Island; confirming the
  Counterspell Delete action removed the correct card and updated totals. These
  were accessibility/context deletion paths, not swipe gestures.
- Logs and final test result bundles: `tmp/swipe-delete-review/`. Screenshots:
  `services/.artifacts/ui-snapshots/swipe-delete/` (both gitignored).

Device Hub drag delivery was inconsistent, sometimes acting as a tap or doing
nothing. Full-swipe, interrupted/reversed/diagonal swipes, row-to-row dismissal,
selection, double-tap coexistence, and revealed-action consistency across every
surface still need reliable gesture testing. No physical-device or spoken
VoiceOver session was performed. Accessibility action availability and deletion
were checked through Device Hub.

The iPad dark/large-text inspection also showed that UIKit-hosted row content
stays light and does not fully scale with the surrounding UI. The existing
context-menu hosting implementation is retained; theme/text propagation is a
separate issue outside this task.

## Manual review

From this worktree:

```sh
make ios-build
make ios-lint
make ios-test IOS_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=18.6'
make ios-snapshot ROUTE=pricing-results
make ios-snapshot ROUTE=pricing-collection
make ios-snapshot ROUTE=pricing-deck
```

For live gestures, launch the built app with `-UI_PREVIEW_ROUTE pricing-results`,
`pricing-collection`, or `pricing-deck` rather than using the snapshot command,
which terminates the app. `undo-navigation` supplies an in-memory tabbed app with
Library collection/deck fixtures; dismiss the simulator camera notice and select
Library. Relaunching these fixtures recreates their disposable data.

On iOS 18 and iOS 26, check each card list and both Library row types:

- Short swipe settles completely open or closed; Delete remains tappable.
- Tap Delete and full swipe each remove only the intended row.
- Card Undo restores the row, including last-card deletion, without a reveal.
- Repeated, reversed, interrupted, and diagonal gestures leave rows usable.
- Scrolling, opening another row, navigation, and context menus dismiss actions.
- Card selection, quantity controls, Results double-tap, and leading foil work.
- Library search-filtered deletion targets the correct collection/deck.
- Native Delete styling matches between Library and card lists on the same OS,
  including dark appearance, large text, iPad, and VoiceOver.

## Code review gate

Every changed production/test file and deletion was reviewed against
`.agents/rules/code-review.md`.

| Criterion | Result | Evidence / limit |
| --- | --- | --- |
| Correctness | PASS | Native action wiring, object identity, disabled selection actions, and retained deletion paths reviewed; tests and observed callbacks pass. Broader gesture matrix remains manual as noted above. |
| Simplicity | PASS | Removes custom gesture/state machinery; short direct action closures; no new abstraction. |
| No scope creep | PASS | Swipe behavior/presentation and directly affected tests only; Library row design and hosting theme issue left unchanged. |
| Meaningful tests | PASS | Rendered Library survivor/rename/empty states and filtered-object persistence coverage retained; context-menu navigation tests adapted; Undo/foil coverage passes. No new public method. |
| Safety | PASS | No force unwraps, new retained closures, secrets, or concurrency changes; existing main-actor deletion paths retained. |
| API contract | N/A | iOS interaction-only change; no backend/schema/provider edits. |
| Artifacts and observability | N/A | No recognition/detection changes. UI evidence and test logs retained separately. |
| Static analysis | PASS | Strict SwiftLint has zero violations; no suppressions; `git diff --check` passes. |
