# Swipe-to-delete rework + stepper fix + leading foil swipe

## Context

Commit `2c8f82b` redesigned list rows with a custom swipe-to-delete gesture on `CollectionItemRow`. Field testing surfaced four UX regressions that together make the lists (Results, Collection detail, Deck detail) feel broken:

1. **Swipe "stops" mid-drag.** `swipeOffset` is clamped to `-deleteButtonWidth * 2` (160pt). There is no visual signal that the commit threshold has been crossed — the red area stays the same width and the trash icon never changes — so the user can't tell whether releasing will delete.
2. **No mid-drag haptic feedback.** Haptics only fire on `onEnded`, after the user has committed.
3. **List can't scroll vertically** when the finger starts on a row. `DragGesture(minimumDistance: 10)` inside `.simultaneousGesture` claims the touch before SwiftUI's List pan recognizer can take over; the `isHorizontalDrag` guard only gates the offset update, not the recognizer itself.
4. **Stepper +/- opens the details page** in Collection and Deck lists. The `interactionOverlay` (`Color.clear` via `.overlay`) is drawn above `rowContent` and swallows every tap, including the Stepper's buttons.

A leading-edge foil toggle was also requested ("plans for adding foil toggle to the cell swipe"). The swipe architecture must host both directions cleanly.

## Approach

### 1. Rework the swipe gesture on `CollectionItemRow`

File: `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/CollectionItemRow.swift`

**Gesture recognizer — UIKit-backed pan**

Replace the SwiftUI `DragGesture` (lines 217–221, 223–252) with a `UIPanGestureRecognizer` exposed through `UIGestureRecognizerRepresentable` (available on iOS 18+; project min is iOS 18).

- New type `HorizontalPanRecognizer: UIViewRepresentable` (or the iOS 18 `UIGestureRecognizerRepresentable`) living in `Features/Shared/HorizontalPanRecognizer.swift`.
- `UIGestureRecognizerDelegate` returns `true` from `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` and implements `gestureRecognizerShouldBegin(_:)` to begin only when `|vx| > |vy|` at the point the pan starts translating. This lets `UIScrollView`'s built-in pan (List) take vertical drags and claims the touch only for horizontal intent.
- Callbacks: `onBegan`, `onChanged(translation:)`, `onEnded(translation:velocity:)`, `onCancelled`.

**Offset model**

Let `swipeOffset` track freely:
- Trailing delete (negative): clamp to `-rowWidth`.
- Leading foil (positive): clamp to `+rowWidth`.
- Remove the spring-back-on-open branch that depends on `openRowID` — closing an open row happens via tap-to-close on the row or when another row opens.

**Two thresholds per direction**

```
openThreshold   = 80    // pt, snap-reveal
commitThreshold = rowWidth * 0.55
```

During `onChanged`, track `@State var crossedCommit: Bool`. When `|offset|` transitions across `commitThreshold`, fire `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` once (both directions: into and out of commit zone). No haptic before opening threshold.

**On release** (`onEnded`):
- `|offset| > commitThreshold` → `commitDelete()` / `commitFoilToggle()` (animate offset to ±rowWidth, heavy haptic, invoke callback).
- `|offset| > openThreshold` → snap open (spring to ±`actionWidth`, medium haptic, register `openRowID`).
- otherwise → `closeSwipe()`.

**Visual — expanding action layer**

Replace the fixed-width `deleteButton` with an `actionLayer` that fills the full row height and width, clipped/offset so its width equals `|swipeOffset|` (plus a small overshoot for spring). Structure:

```
ZStack(alignment: .trailing) {                 // trailing action (delete)
    actionBackground(color: .systemRed, alignment: .trailing)
        .frame(width: max(0, -swipeOffset))
    actionIcon("trash", centered: crossedCommit)
}
ZStack(alignment: .leading) {                  // leading action (foil)
    actionBackground(color: .systemBlue, alignment: .leading)
        .frame(width: max(0, swipeOffset))
    actionIcon("sparkles", centered: crossedCommit)
}
rowContent
    .offset(x: swipeOffset)
    .clipShape(RoundedRectangle(cornerRadius: min(abs(swipeOffset) / 10, 8), style: .continuous))
```

- While the row is below the commit threshold, the icon sits pinned to the trailing/leading edge inside the (narrow) reveal strip — current behavior preserved visually.
- Once `crossedCommit == true`, the icon slides to the center of the revealed area (or stays pinned and scales up ~1.2×) to signal "release to delete/toggle." This, plus the expanding red/blue background, is the visual threshold indicator the user asked for.
- On `commitDelete()`, animate `swipeOffset` to `-rowWidth` (full-bleed red) before the callback fires — the existing `completionCriteria: .logicallyComplete` pattern already supports this.

**Bidirectional action plumbing**

Add a new parameter to `CollectionItemRow`:

```swift
var onSwipeToggleFoil: (() -> Void)?
```

The leading branch renders only when `onSwipeToggleFoil != nil`; the trailing branch renders only when `onSwipeDelete != nil`. The `handleDragChanged` / `handleDragEnded` logic branches on `sign(swipeOffset)` and consults the matching closure.

### 2. Remove the full-row tap overlay; fix Stepper tap-through

Still in `CollectionItemRow.swift`.

- Delete `interactionOverlay` (lines 90–99) and its attachment on `rowContent` (line 76).
- Wrap the tappable region — thumbnail + `cardNameRow` + `metaRow` + `priceColumn` — in a single `Button(action: onNavigate ?? {})` with `.buttonStyle(.plain)`. The Stepper sits in `cardDetails` as a sibling that is NOT inside that Button, so its `.borderless` +/- buttons receive taps first.
- Apply `.buttonStyle(.borderless)` to the `Stepper` to ensure its hit-test wins and to prevent List row selection cascades on iOS 18.
- When a swipe is open (`swipeOffset != 0`), intercept the navigation tap: wrap the Button's action closure with `guard swipeOffset == 0 else { closeSwipe(); return }`.

Layout sketch:

```swift
HStack(spacing: Spacing.md) {
    Button {
        if swipeOffset != 0 { closeSwipe() } else { onNavigate?() }
    } label: {
        HStack(spacing: Spacing.md) {
            cardThumbnail
            VStack(alignment: .leading, spacing: Spacing.xs) {
                cardNameRow
                metaRow
            }
            Spacer(minLength: Spacing.lg)
            priceColumn
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)

    if showQuantityStepper {
        quantityStepper
            .buttonStyle(.borderless)
            .fixedSize()
    }
}
```

The Stepper then lives outside the navigation Button, so it cannot trigger `onNavigate`.

### 3. Wire leading-swipe foil toggle in all three lists

- `Features/Results/ResultsView.swift` (line 141):
  `onSwipeToggleFoil: { toggleFoil(item) }` — reuses existing `toggleFoil(_:)` (line 325) which calls `toggleFoilUnconditionally()` and refetches price.
- `Features/Library/CollectionDetailView.swift` (line 121): add `onSwipeToggleFoil: { toggleFoil(item) }`; add a private `toggleFoil(_:)` helper that calls `item.toggleFoilIfNoDuplicate(in: collection.items)` with a `UIImpactFeedbackGenerator(style: .medium)` haptic. If the toggle is refused (duplicate would result), snap the row closed and fire `UINotificationFeedbackGenerator().notificationOccurred(.warning)`.
- `Features/Library/DeckDetailView.swift` (line 154): same pattern, using `deck.items`.

Note: `toggleFoilIfNoDuplicate` guards against producing duplicate (card, foil) pairs in a collection/deck. Keep that guard — do not add `toggleFoilUnconditionally` in library contexts.

### 4. Close-on-scroll behavior

With `openRowID` still in play, tapping another row or scrolling past shouldn't leave orphaned open rows. Add: on `scrollDisabled` state change or via a `.onChange(of: scrollPhase)` (iOS 18 `ScrollView` API isn't available on `List`, so instead) — simpler: attach a `.simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { ... })` to the list background that closes any open row. If that conflicts, skip this and rely on `openRowID` + tap-to-close only.

## Critical files

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/CollectionItemRow.swift` — swipe mechanics, tap/nav restructure, foil action parameter
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/HorizontalPanRecognizer.swift` — **new**, UIKit pan wrapper
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Results/ResultsView.swift` — pass `onSwipeToggleFoil`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/CollectionDetailView.swift` — pass `onSwipeToggleFoil`, add local `toggleFoil`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/DeckDetailView.swift` — same

Reused utilities:
- `CollectionItem.toggleFoilIfNoDuplicate(in:)` / `toggleFoilUnconditionally()` — already exist.
- Existing `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` usage pattern in `handleDragEnded` and `commitDelete`.
- `openRowID` single-open-row coordination — retained as-is.

## Verification

Run from the worktree root:

1. Baseline (should already pass):
   - `make ios-build`
   - `make ios-lint`
   - `make ios-test`
2. Unit tests — add coverage in `MTGScannerKit/Tests/MTGScannerKitTests/`:
   - A model-level test that asserts `CollectionItemRow`'s published threshold constants behave as expected if the swipe logic is extracted into a testable pure function (`SwipeState.resolve(offset:rowWidth:velocity:) -> SwipeOutcome`). Extracting the state machine is recommended so threshold logic is unit-testable without instantiating a SwiftUI view.
3. Snapshot:
   - `make ios-snapshot ROUTE=results` — add swipe-open and swipe-committed states to `ResultsFixtureView` so regressions are visible in PR diffs.
4. Manual on simulator (iPhone 16, iOS 18):
   - Vertical scroll: start finger on a row, drag up/down — list scrolls smoothly, row does not swipe.
   - Short horizontal swipe (~80pt): row snaps open, delete button visible, medium haptic fires.
   - Long horizontal swipe (past commit threshold): red area expands full-width, trash icon re-centers, medium haptic fires mid-drag, release → row deletes with heavy haptic.
   - Leading swipe (right): blue sparkles area expands; release past commit → foil toggles; in Collection/Deck, a duplicate-foil attempt snaps closed with warning haptic and no state change.
   - In Collection/Deck detail: tap Stepper `+` / `-` — quantity changes, details sheet does NOT appear.
   - Tap anywhere else on the row body — details still navigate/present as before.
