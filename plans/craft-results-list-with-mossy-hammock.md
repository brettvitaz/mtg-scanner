# Craft: Results list row redesign

## Context

The scanner's results list (and, by decision, the sibling Collection- and Deck-detail
lists that share the same row component) currently renders with SwiftUI's default
`.insetGrouped` chrome: floating rounded cards, hard-coded `.orange/.yellow/.gray`
rarity swatches, system fonts, and a tiny caption-sized price line. Geist has already
been registered in `FontRegistry.swift` but is unused; there are no design tokens; and
`.orange/.yellow/.gray` read as flat system colors under both light and dark mode.

The craft brief (`.impeccable.md`) positions this product as a precision instrument —
Bloomberg-terminal density with *rarity* as the only chromatic vocabulary, Geist +
Geist Mono typography, and OKLCH-tinted neutrals. The user wants three concrete
changes on top of that direction:

1. Redesigned cells showing **card name, set, rarity, and price**.
2. **No rounded corners at rest** — corners appear only as a cell is swiped in.
3. A **subtle color overlay** on each cell encoding its rarity.

Per decisions captured during planning: price shows **sell and buy at equal weight**
(both in Geist Mono); the refactor **replaces the shared `CollectionItemRow`** so all
three screens adopt the new design; swipe uses a **custom `DragGesture`** so the
corner radius can animate in lockstep with swipe progress (native `.swipeActions`
does not expose that progress).

## Design decisions

- **List chrome.** Switch all three lists from `.insetGrouped` to `.plain`. Rows go
  edge-to-edge (`.listRowInsets(EdgeInsets())`), draw their own hairline separator
  via `.listRowSeparator(.hidden)` + a 1px `Rectangle().fill(Color.dsBorder)` at the
  bottom of each row, and set `.listRowBackground(Color.clear)` so the row owns its
  rarity overlay.
- **Rarity overlay.** Applied as the row's background: `Rarity.overlayColor` at
  ~6% opacity in light mode / ~10% in dark mode. Subtle enough to read as tint, not
  as a state highlight. `Rarity.common` renders no overlay (neutral).
- **Typography.** Card name → Geist 15pt/500. Meta line (set code · collector
  number · rarity label) → Geist Mono 11pt/400, `--text-secondary`. Prices → Geist
  Mono 13pt/500, `--text-primary`. Sell/buy axis labels → Geist Mono 10pt/400,
  `--text-secondary`. Matches the brief's type scale.
- **Row layout.**
  ```
  [60×84 thumbnail]  Card Name                    sell  $12.45
                     RIX · #183 · RARE             buy   $9.10
  ```
  Prices are right-aligned in a monospaced trailing column so digits line up
  vertically across rows. "RARE" label in meta line uses the rarity color for
  non-color-blind-only reinforcement.
- **Swipe.** Custom `DragGesture(minimumDistance: 10)`. As the row translates left,
  corner radius animates `0 → 8pt` linearly until `|offset| == 80pt`. At 80pt the
  row snaps open, revealing a trailing Delete action. Past ⅔ of row width the
  gesture commits full-swipe delete with haptic. Snap-close on tap anywhere else;
  only one row may be open at a time via a parent-owned `@State private var
  openRowID: UUID?`.
- **Selection mode unchanged.** When `editMode == .active`, swipe is disabled and
  the row renders without navigation or custom gesture (preserves existing
  bulk-select flow).
- **Accessibility.** Custom swipe replaces native `.swipeActions`, so each row
  adds `.accessibilityAction(named: "Delete") { … }`. Existing `.contextMenu` is
  preserved. Rarity-as-color is reinforced by the "RARE" text label in the meta
  line (brief requirement: non-color state indicators).

## Files — new

- **`apps/ios/MTGScannerKit/Sources/MTGScannerKit/Support/DesignTokens.swift`**
  Semantic color tokens backed by `UIColor(dynamicProvider:)` so light/dark adapt at
  the OS level. Exposes `Color.dsBackground`, `dsSurface`, `dsBorder`, `dsTextPrimary`,
  `dsTextSecondary`, `dsAccent`. Values from the brief's OKLCH table, converted to
  sRGB/P3 via `UIColor(red:green:blue:alpha:)` at load time (no runtime OKLCH math —
  SwiftUI has no native OKLCH initializer). Also exposes a `Spacing` enum
  (`.xs=4, .sm=8, .md=12, .lg=16, .xl=24, .xxl=32`) for consistent numeric use.

- **`apps/ios/MTGScannerKit/Sources/MTGScannerKit/Support/Rarity.swift`**
  `enum Rarity: String, CaseIterable { case common, uncommon, rare, mythic }`.
  - `init?(_ raw: String?)` — case-insensitive, trims, tolerates nil.
  - `badgeColor: Color` — solid swatch for labels/badges.
  - `overlayColor(for scheme: ColorScheme) -> Color` — opacity 0.06 light / 0.10
    dark. Common returns `.clear`.
  - `shortLabel: String` — "COMMON", "UNCOMMON", "RARE", "MYTHIC".

- **`apps/ios/MTGScannerKit/Sources/MTGScannerKit/Support/Typography.swift`**
  `extension Font { static func geist(...); static func geistMono(...) }` with
  named sizes from the brief table (`.screenTitle, .sectionHeading, .cardName,
  .meta, .caption, .priceMono, .confidenceMono`). Uses `Font.custom("Geist-*", size:)`
  — PostScript names match registered filenames per `FontRegistry.swift`.

- **`apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RarityTests.swift`**
  Tests `Rarity.init(_:)` parses case-insensitively, trims whitespace, returns nil
  for unknown/empty strings, and that `overlayColor(for: .dark) != .clear` for every
  rarity except `.common`. Six small tests.

## Files — modified

- **`apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/CollectionItemRow.swift`**
  Primary work. Restructure as a `ZStack(alignment: .trailing)`:
  1. **Background layer** — Delete `Button` pinned to the trailing edge (revealed
     during swipe).
  2. **Foreground layer** — existing content laid out per design decisions above,
     wrapped in `.background(rarityOverlay).clipShape(RoundedRectangle(cornerRadius:
     dynamicCornerRadius))`, offset by `swipeOffset`, with `.gesture(dragGesture)`.

  New row state:
  ```swift
  @Binding var openRowID: UUID?   // parent-owned "only one open" coordinator
  @State private var swipeOffset: CGFloat = 0
  private var isOpen: Bool { openRowID == item.id }
  private var cornerRadius: CGFloat { min(abs(swipeOffset) / 10, 8) }
  ```

  Gesture:
  ```swift
  DragGesture(minimumDistance: 10)
      .onChanged { value in
          // clamp to [-rowWidth, 0] for trailing-only swipe
          swipeOffset = min(0, max(value.translation.width, -rowWidth))
      }
      .onEnded { value in
          let fullSwipe = -value.translation.width > rowWidth * 0.66
          if fullSwipe {
              UINotificationFeedbackGenerator().notificationOccurred(.warning)
              onDelete?()
          } else if -value.translation.width > 40 {
              openRowID = item.id
              withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                  swipeOffset = -80
              }
          } else {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                  swipeOffset = 0
              }
              if isOpen { openRowID = nil }
          }
      }
  ```

  Watch `openRowID` via `.onChange`; animate `swipeOffset` back to `0` when another
  row opens. Tap elsewhere on the row closes via the same mechanism.

  Replace inline `RarityCircle` with a small mono-typed label derived from
  `Rarity.shortLabel`, tinted with `rarity.badgeColor`.

  Replace `priceLabel` caption with the new two-axis price column. Both prices
  always render Geist Mono; when a value is nil show an em dash.

  Variant control: introduce `enum Variant { case results, collection }`. Variant
  gates the quantity stepper and swipe (Results gets both; Collection gets stepper,
  swipe is still on); variant also gates the meta line's appearance of the foil
  sparkle vs. a FOIL tag position. Existing public API of the row (`item`,
  `showQuantityStepper`, `onCopy/onMove/onDelete/onToggleFoil`) is preserved —
  only the new `openRowID` binding is added.

  Remove `private struct RarityCircle`. Keep `accessibilitySummary` method;
  append a `.accessibilityAction(named: "Delete")` when `onDelete != nil`.

- **`apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Results/ResultsView.swift`**
  - Change `.listStyle(.insetGrouped)` → `.listStyle(.plain)`.
  - Add `@State private var openSwipeRowID: UUID?` to the view.
  - On the `List`, add `.listRowSeparator(.hidden)`, `.listRowInsets(EdgeInsets())`,
    `.listRowBackground(Color.dsBackground)`, and `.scrollContentBackground(.hidden)`
    with `.background(Color.dsBackground)` on the parent so the list matches tokens.
  - In `cardRowView(for:)`, pass `openRowID: $openSwipeRowID` to `CollectionItemRow`.
  - **Remove** the existing `.swipeActions(edge: .trailing, ...)` modifier — the row
    now owns its swipe.
  - Wrap rows in `NavigationLink` as today, but prefer `.navigationDestination` +
    programmatic push guarded by `swipeOffset == 0` so a drag does not fire
    navigation. Keep the `TapGesture(count: 2)` foil-toggle gesture.
  - Header style: update `cardListHeader` typography to Geist 11pt/500 uppercased,
    `--text-secondary`, consistent with the brief's section heading treatment.
  - Empty state: swap `.title3.bold()` → `.geist(.sectionHeading)`; `.subheadline`
    → `.geist(.meta)`; tint the magnifying-glass icon with `Color.dsTextSecondary`.

- **`apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/CollectionDetailView.swift`**
  Same list-style / token changes as ResultsView. Thread a local
  `@State private var openSwipeRowID: UUID?` into each `CollectionItemRow`. Preserve
  the existing trailing Delete swipe semantics via `onDelete` callback. Keep the
  quantity stepper (variant `.collection`).

- **`apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/DeckDetailView.swift`**
  Same pattern as CollectionDetailView.

- **`apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetail/CardDetailSubviews.swift`**
  Update `RarityBadge` to consume the new `Rarity` enum and `badgeColor` so both
  the row and the detail screen use one source of truth for rarity color. No
  visual change intended on the detail view.

## Files intentionally not changed

- `CollectionModels.swift` — `rarity` remains `String?` in storage; the new `Rarity`
  enum is a view-layer concern. Keeps the SwiftData schema stable.
- `CardFilterSort.swift` — `RarityFilter` stays as-is; it's used only for filter UI
  and already has the four cases.
- Price formatting — prices remain backend-supplied `String?` (e.g. `"$12.45"`).
  Not in scope to introduce a client-side formatter.
- Font registration — already in place; no changes.

## Verification

1. **Static analysis.** `make ios-lint` and `make lint` must pass. No new
   `swiftlint:disable` suppressions.
2. **Unit tests.** `make ios-test` runs the full XCTest suite — confirm new
   `RarityTests` and existing `AccessibilitySummaryTests`,
   `CollectionItemFromPrintingTests`, `CollectionItemFoilToggleTests`,
   `CollectionItemMoveTests` all pass.
3. **Build.** `make ios-build` produces a clean Debug build against the
   `iphonesimulator` SDK.
4. **Visual snapshot.** `make ios-snapshot-all` currently captures `settings` and
   `scan`. Add a `results` route in
   `apps/ios/MTGScannerKit/Sources/MTGScannerFixtures/PreviewGalleryRootView.swift`
   that renders `ResultsView` with a fixture array covering all four rarities in
   both light and dark mode, then run:

   ```bash
   make ios-build
   make ios-snapshot ROUTE=results
   ```

   Inspect `services/.artifacts/ui-snapshots/results.png` for:
   - Rows edge-to-edge, flat corners at rest.
   - Rarity overlays visibly distinct (mythic/rare/uncommon/common) but subtle.
   - Prices aligned right, mono-typed, both visible.
   - Geist renders (not system San Francisco).
   - Light and dark both read correctly.

5. **Manual swipe check** in Simulator: `make ios-build && make ios-test` boots the
   sim; open the app, scan a card (or rely on seeded fixture data in Results),
   swipe-drag a row slowly and confirm corners round in lockstep. Swipe past 80pt
   and release → row snaps open with Delete. Full-swipe to commit delete. Open one
   row, swipe another → first row snaps closed. Toggle selection mode → swipe is
   disabled.

6. **Accessibility spot-check.** Enable VoiceOver in the Simulator; confirm rows
   still announce via `accessibilitySummary` and that a "Delete" custom action is
   available via the rotor.

## Post-implementation review (mandatory per CLAUDE.md)

Run the code-review gate against every changed file using `.claude/rules/code-review.md`
and state pass/fail on each criterion. Pay particular attention to:
- Functions under 30 lines (the new row's gesture + state management is the risk).
- No force unwraps in the new gesture code.
- `@MainActor` correctness on the row (SwiftUI views implicitly MainActor; any
  `UIImpactFeedbackGenerator` calls must stay on main).
- Swipe gesture does not fight `NavigationLink` tap or `.contextMenu` long-press.
