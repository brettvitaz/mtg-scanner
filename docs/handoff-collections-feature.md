# Collections Feature — Handoff Document

**Branch**: `add-collections-feature`
**Base**: `master` at `ca22723`
**Date**: 2026-03-30
**Status**: Implemented, builds and tests pass. Not yet merged to master.

---

## 1. What This Feature Does

Adds a persistent card collections system to the MTG Scanner iOS app. Previously, scan results were ephemeral — each new scan replaced the previous one. Now:

- Scanned cards persist in a **results inbox** across scans until manually removed or moved.
- Users can organize cards into **collections** and **decks** via a new **Library tab**.
- Card lists support **iOS Mail-style multi-select editing**: tap Select, choose items via checkboxes, then bulk Move, Copy, or Delete.
- Cards in any list (results, collection, deck) can be **exported as JSON or CSV** via the system share sheet.
- Cards can be **added to a collection or deck directly from the card detail view**.

---

## 2. Architecture

### Persistence: SwiftData (iOS 17+)

The project already targeted iOS 17.0. SwiftData was chosen over Codable+FileManager or CoreData because:
- Native iOS 17 framework — no version bump needed.
- `@Model` macro eliminates boilerplate.
- `@Query` in views provides automatic reactivity.
- `@Relationship` with cascade delete handles referential integrity.

The model container is created in `MTGScannerApp.swift` and the `mainContext` is passed to `AppModel` and `LibraryViewModel` via `onAppear`.

### Data Model

Three `@Model` classes in `Models/CollectionModels.swift`:

```
CollectionItem (@Model)
├── id: UUID
├── title, edition, setCode, collectorNumber, foil, rarity
├── typeLine, oracleText, manaCost, power, toughness, loyalty, defense
├── scryfallId, imageUrl, setSymbolUrl, cardKingdomUrl
├── addedAt: Date
├── collection: CardCollection?  (inverse relationship)
└── deck: Deck?                  (inverse relationship)

CardCollection (@Model)
├── id: UUID
├── name: String
├── items: [CollectionItem]  (cascade delete)
├── createdAt: Date
└── updatedAt: Date

Deck (@Model)
├── id: UUID
├── name: String
├── items: [CollectionItem]  (cascade delete)
├── createdAt: Date
└── updatedAt: Date
```

**Results inbox** = items where `collection == nil && deck == nil`. This is queried via `@Query` with a `#Predicate`.

A `CollectionItem` belongs to at most one `CardCollection` OR one `Deck`, never both. Moving an item sets one relationship and nils the other.

### Navigation

```
RootTabView (TabView, 4 tabs)
├── Scan (tag 0)          — unchanged
├── Results (tag 1)       — persistent inbox with mail-style edit
├── Library (tag 2)       — NEW: collections and decks lists
│   ├── CollectionDetailView  — items in a collection
│   └── DeckDetailView        — items in a deck
└── Settings (tag 3)      — shifted from tag 2
```

### File Inventory (11 new, 6 modified)

**New production files** (all under `apps/ios/MTGScanner/`):

| File | Purpose |
|------|---------|
| `Models/CollectionModels.swift` | SwiftData models: CollectionItem, CardCollection, Deck |
| `Features/Library/LibraryView.swift` | Library tab root: lists collections and decks |
| `Features/Library/LibraryViewModel.swift` | Create/delete logic for collections and decks |
| `Features/Library/CollectionDetailView.swift` | Collection items list with edit mode |
| `Features/Library/DeckDetailView.swift` | Deck items list with edit mode (move/copy/delete) |
| `Features/Shared/CollectionItemRow.swift` | Shared card row component (thumbnail + info) |
| `Features/Shared/MoveToSheet.swift` | Destination picker for move/copy operations |
| `Features/Shared/ExportButton.swift` | Export menu content + UIActivityViewController bridge |
| `Services/ExportService.swift` | JSON and CSV export generation |

**New test files** (under `apps/ios/MTGScannerTests/`):

| File | Coverage |
|------|----------|
| `CollectionModelsTests.swift` | Model init, RecognizedCard conversion, correction application, duplicate, edge cases |
| `ExportServiceTests.swift` | JSON/CSV generation, empty input, comma/quote escaping |

**Modified files**:

| File | Change |
|------|--------|
| `App/MTGScannerApp.swift` | SwiftData ModelContainer setup, LibraryViewModel injection |
| `App/AppModel.swift` | `modelContext` property, `persistRecognizedCards()` inserts items after scan |
| `App/RootTabView.swift` | Added Library tab at index 2, shifted Settings to index 3 |
| `Features/Results/ResultsView.swift` | Complete rewrite: SwiftData query, mail-style edit, export |
| `Features/CardDetail/CardDetailView.swift` | "Add to Collection or Deck" button, toast overlay |
| `project.pbxproj` | All new files registered |

---

## 3. Key Decisions

### CollectionItem is a snapshot, not a reference

When a card is added to a collection, a `CollectionItem` is created with the card's data at that moment. It does not maintain a live link to the recognition result or API. This was deliberate:
- Corrections are baked in at creation time via `init(from:correction:)`.
- The same card can exist in multiple collections/decks as separate `CollectionItem` instances (via `duplicate()`).
- `scryfallId` is preserved for future price/printing lookups.

### toRecognizedCard() reuses the item's UUID

`CollectionItem.toRecognizedCard()` passes `id: id` to the `RecognizedCard` initializer. This is critical because `NavigationLink(value:)` evaluates its value eagerly on every SwiftUI body re-evaluation. If a new UUID were generated each time, it would create duplicate navigation entries and break the back button. This was a bug that was discovered and fixed during development.

### Selection uses Set<UUID>, not Set<PersistentIdentifier>

SwiftUI's `List(selection:)` requires the selection set's element type to match the `Identifiable.ID` of the ForEach content. `CollectionItem` has `var id: UUID` as its `Identifiable` identity, so selection must use `Set<UUID>`. Using `Set<PersistentIdentifier>` (SwiftData's internal ID) caused selection circles to not render and taps to not register. This was a bug that required multiple iterations to diagnose.

### NavigationLink is conditional on edit mode

In select mode, rows must NOT be wrapped in `NavigationLink` because `NavigationLink` intercepts taps and prevents SwiftUI's built-in selection mechanism from working. The pattern is:

```swift
ForEach(items) { item in
    if isSelecting {
        CollectionItemRow(item: item)          // plain row — tappable for selection
    } else {
        NavigationLink(value: item.toRecognizedCard()) {
            CollectionItemRow(item: item)       // navigable row
        }
    }
}
```

### DeckDetailView actions are in an extension

`DeckDetailView` exceeded SwiftLint's 200-line type body length limit. The action methods (enterSelecting, exitSelecting, selectAll, moveSelectedItems, copySelectedItems, deleteSelectedItems) were moved to `extension DeckDetailView` to keep the struct body under the limit. These methods are `func` (not `private func`) because Swift extensions cannot declare private members for the extended type in the same file.

### Export uses ExportMenuContent, not a standalone button

Originally `ExportButton` was a self-contained `Menu` view. This didn't nest well inside other menus (the "..." overflow). It was refactored to `ExportMenuContent` — a view that renders `ForEach(ExportFormat.allCases)` buttons, intended to be placed inside a parent `Menu`. The export sheet state (`@State var exportFile: ExportActivityItem?`) lives in the parent view.

### ModelContext injection via onAppear

`AppModel` and `LibraryViewModel` receive their `ModelContext` via property assignment in `MTGScannerApp.onAppear`, not via `@Environment`. This is because they are `ObservableObject` classes created as `@StateObject` — they exist before the SwiftUI environment is available. The `guard let modelContext` pattern in both classes handles the brief nil window during first render.

---

## 4. Known Limitations and Gaps

### No item-level detail view for CollectionItem

Tapping a card in a collection or deck navigates to `CardDetailView`, which takes a `RecognizedCard`. The conversion via `toRecognizedCard()` works but loses the `CollectionItem` identity — edits in `CardDetailView` (corrections, edition selection) do not update the `CollectionItem` in SwiftData. A dedicated `CollectionItemDetailView` that operates on the `@Model` directly would be a better long-term solution.

### Corrections are not migrated

The existing `CardCorrection` system (UserDefaults-based, keyed by `RecognizedCard.id`) is still present and functional for the scan flow. When a card is persisted to SwiftData, corrections are applied at creation time. But there is no mechanism to edit a `CollectionItem` after it has been saved — the "Save Correction" button in `CardDetailView` still writes to the old UserDefaults-based corrections dictionary.

### No search or filter

Collection, deck, and results lists have no search bar or filter mechanism.

### No rename for collections/decks

Collections and decks can be created and deleted but not renamed after creation.

### Duplicate detection

Adding the same card to a collection multiple times creates separate `CollectionItem` instances. There is no deduplication or quantity tracking.

### Pre-existing lint violations

Two SwiftLint violations exist that predate this feature:
- `APIClient.swift:131` — trailing comma (untouched file)
- `CardDetailView.swift` — file length > 400 lines (was 423 before this feature, now 467)

### Pre-existing test failure

`RectangleFilterTests.testFilterAcceptsAtUpperToleranceBound()` fails on both master and this branch. Unrelated to collections.

---

## 5. Commit History

```
78de257 fix(ios): fix selection circles and double navigation in card lists
967c3ef fix(ios): enable selection circles and tap-to-select in edit mode
03697ef fix(ios): show selection circle indicators in edit mode
4fec5b5 feat(ios): add collections, decks, and persistent results
```

The first commit (`4fec5b5`) contains the full feature. The subsequent three commits fix the multi-select UI — selection circles not appearing and tap-to-select not working. The root causes were: selection Set type mismatch (`PersistentIdentifier` vs `UUID`), `NavigationLink` intercepting taps in edit mode, and `toRecognizedCard()` generating unstable UUIDs.

---

## 6. Verification

**Build**:
```bash
cd mtg-scanner-worktrees/add-collections-feature
xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner \
  -sdk iphonesimulator -configuration Debug build
```

**Tests**:
```bash
xcodebuild test -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
All new tests pass (16/16). One pre-existing failure in RectangleFilterTests.

**Lint**:
```bash
make ios-lint
```
No new violations. Two pre-existing violations (see Known Limitations).

**Manual testing checklist**:
- [ ] Scan a card — results appear in Results tab and persist across app relaunch
- [ ] Tap Select — circle indicators appear on each row, tapping rows toggles selection
- [ ] Select All selects all items, X exits selection mode
- [ ] Move selected items to a new collection — items disappear from inbox, appear in collection
- [ ] Library tab shows the new collection with correct item count
- [ ] Tap a card in a collection — detail view loads, back button returns to collection (single tap)
- [ ] In deck detail, select items and Copy to Collection — originals remain in deck, copies appear in collection
- [ ] Export as JSON from "..." menu — share sheet appears with valid JSON file
- [ ] Export as CSV — share sheet appears with valid CSV file
- [ ] Delete items from a collection — confirmation dialog, items removed
- [ ] Add to Collection from card detail — toast confirms, card appears in chosen collection

---

## 7. Dependency Check

- **No external dependencies added.** SwiftData is part of iOS 17 SDK.
- **No environment variables or configuration changes.**
- **No backend API changes.** This is iOS-only.
- **No secrets or credentials.**
- **Xcode project file updated** (`project.pbxproj`) to include all 11 new Swift files with correct group membership and build phase entries.
- **iOS simulator runtime required**: iOS 26.4 (installed via `xcodebuild -downloadPlatform iOS`). iPhone 17 Pro simulator used for testing.
- **All file paths in this document are relative to the worktree** at `mtg-scanner-worktrees/add-collections-feature/` unless otherwise noted.
