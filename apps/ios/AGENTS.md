# iOS App — apps/ios

SwiftUI app for iPhone-first MTG card scanning with on-device detection and cropping.

## Structure

The iOS code is split into two parts:

- **`MTGScanner/`** — Xcode app shell: `@main` entry point, `Info.plist`, `Assets.xcassets`, `MTGCardDetector.mlpackage`. This is the Xcode target that produces the `.app`.
- **`MTGScannerKit/`** — Swift Package with two targets: `MTGScannerKit` (production source + tests) and `MTGScannerFixtures` (debug/simulator fixture code + images). SourceKit-LSP indexes this package for IDE tooling (autocomplete, go-to-definition).
- **`MTGScanner.xcworkspace`** — Workspace that references both. **Always open the workspace, not the xcodeproj.**

## Detection pipeline

1. `CameraSessionManager` delivers `CMSampleBuffer` frames on a dedicated serial queue.
2. `CardDetectionEngine` processes frames on `visionQueue` (one in flight at a time — drops excess frames).
3. **Scan mode**: `VNDetectRectanglesRequest` → `RectangleFilter`, with throttled YOLO validation through `ScanYOLOValidationState`.
4. **Auto Scan mode**: `YOLOCardDetector` detects cards for the scanning-station flow. Convert its top-left-origin boxes into Vision bottom-left-origin coordinates before tracking.
5. `CardTracker` smooths results with EMA on positions + presence hysteresis.
6. `DetectionOverlayRenderer` draws `CAShapeLayer` overlays on the preview layer (main thread).

## Critical coordinate transform rules

These were established through debugging. Do not deviate:

- **VNDetectRectanglesRequest**: Pass native landscape `CVPixelBuffer` to `VNImageRequestHandler` with **no orientation hint**. Vision detects rectangles within the specified aspect-ratio range regardless of the card's orientation relative to the sensor, so no hint is needed. An orientation hint would cause Vision to return coordinates in a rotated space that mismatches `layerPointConverted`'s expected native sensor input.
- **Vision → screen**: Use `previewLayer.layerPointConverted(fromCaptureDevicePoint:)` — do NOT attempt manual coordinate math. Apply Y-flip first (Vision origin is bottom-left, capture device origin is top-left). `layerPointConverted` handles `videoRotationAngle` and `resizeAspectFill` for all device orientations automatically.
- **Pipeline**: native landscape buffer → Vision normalized coords (native sensor space) → Y-flip → `layerPointConverted` → screen points. This works for portrait, landscape left/right, and portrait upside-down.
- **Interface orientation**: iPhone uses portrait throughout the app; iPad retains portrait and landscape left/right. `Info.plist` declares this policy with `UISupportedInterfaceOrientations` and its `~ipad` variant. Do not override orientation from scan-view lifecycle callbacks. Keep `CameraViewController.updatePreviewOrientation` and the orientation-aware coordinate mapping for iPad; native sensor buffers and imported-image orientation handling are independent of the interface policy.

## Coding rules

- Swift 6.0, minimum iOS 18.0 (supports iOS 18 and iOS 26).
- `final class` for view models and services (prevent unintended subclassing).
- `@MainActor` on all UI-bound classes. Bridge from background with `Task { @MainActor in }`.
- No force unwraps (`!`) in production code. `guard let` / `if let` only.
- `[weak self]` in closures on long-lived objects to prevent retain cycles.
- Camera and Vision work on dedicated serial `DispatchQueue`s, never on main thread.
- `CATransaction.setDisableActions(true)` when updating overlay layer paths to prevent implicit animations.
- Session preset: `.hd1920x1080`. Do not use `.photo` or `.hd4K` — too slow for real-time Vision.
- Classes that use GCD-based concurrency (camera/detection layer) are marked `@unchecked Sendable` — do not remove this without auditing the threading model.

## Testing

Do not use `swift test` for this iOS package. Use `make ios-test` or run `xcodebuild test` directly against the workspace and the appropriate scheme.

```bash
xcodebuild test \
  -workspace apps/ios/MTGScanner.xcworkspace \
  -scheme MTGScanner \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  2>&1 | xcpretty
```

Or via Makefile: `make ios-test`

- Logic tests in `MTGScannerKit/Tests/MTGScannerKitTests/`; UI workflows in `MTGScannerUITests/`.
- For interactive changes, run the relevant UI workflow with `make ios-ui-test` alongside logic tests and screenshot inspection. If existing coverage cannot exercise the changed interaction, add a workflow using the production controls, stable accessibility identifiers, and bounded condition waits. Report commands, results, artifacts, and coverage gaps.
- The initial UI workflow covers saved-card Non-foil → Foil, Save dismissal, and persistence after termination/relaunch. It does not cover other interactions.

- Native price-field interaction tests live in `MTGScannerTests/` and require the app host:
  `make ios-test IOS_TEST_SCHEME=MTGScanner`. This also runs `MTGScannerUITests/` for price toolbar, Return, and sheet flows.
  The package runner has no application for dispatching UIKit actions. Set `IOS_TEST_SIMULATOR_ID` to an isolated simulator
  when another task is using the default device.
- `final class <Feature>Tests: XCTestCase` naming.
- Use `XCTUnwrap` for required optional values in tests; SwiftLint also checks test files.
- Use `XCTAssertEqual(_:_:accuracy:)` for CGFloat/Double comparisons.
- Test models and pure logic, including filters, tracking, YOLO validation, and decoding.
- If you need to target the Swift package tests directly, run `xcodebuild test` with the `MTGScannerKitTests` scheme rather than `swift test`.
- Pin simulator OS in scripted commands. `name=iPhone 16` alone resolves to `OS:latest`, which can fail when latest runtimes only have newer device families.

### UI workflow command and artifacts

```bash
make ios-ui-test
make ios-ui-test IOS_UI_TEST_FILTER=MTGScannerUITests/CardFinishTests/testEditFinishPersistsAfterRelaunch
make ios-ui-test IOS_UI_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17,OS=26.4'
make ios-ui-test IOS_UI_TEST_RESULT_BUNDLE=tmp/my-ui-run.xcresult
```

The dedicated `MTGScannerUITests` scheme defaults to iPhone 16 / iOS 18.6.
`ios-test` continues to run logic tests independently. Each UI command keeps a unique
`tmp/ios-ui-tests-<timestamp>-<UUID>.xcresult` unless a result path is supplied; use a
new path on each run. Failures propagate through make. Open the bundle in Xcode for
failure diagnostics and screenshots. Successful runs also retain named initial-detail,
editor, saved-detail, and relaunched-detail attachments. Export PNGs for visual review:

```bash
xcrun xcresulttool export attachments --path tmp/my-ui-run.xcresult --output-path tmp/my-ui-attachments
```

The DEBUG-only harness reads `UI_TEST_RUN_ID` (a UUID) and `UI_TEST_MODE` from the
test app's launch environment before opening storage. `fresh` resets only that run's
`Application Support/UITestRuns/<UUID>/` disk store and
`com.brettvitaz.mtgscanner.ui-tests.<UUID>` preferences suite, then seeds one card.
`resume` requires the existing store and never reseeds. Test teardown launches
`cleanup`, which removes only that run's resources. An interrupted runner may leave
its isolated resources behind; a later run uses a new UUID. Normal app data is untouched.

The harness opens the production detail/editor views. A process-local URL protocol
returns deterministic price fixtures and crashes visibly on unexpected HTTP requests;
no backend, network connection, or API keys are needed. Extend fixtures explicitly
when a new workflow needs another endpoint. Keep all harness code behind `#if DEBUG`.

## Build verification

Minimum check that the app compiles:

```bash
xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner \
  -sdk iphonesimulator -configuration Debug \
  -resultBundlePath tmp/ios-build-result.xcresult build
```

Or: `make ios-build`

`make ios-build` also refreshes the package-local `buildServer.json` used by SourceKit-LSP and writes an Xcode result bundle so VS Code can keep Swift compile flags in sync.

## UI iteration for agents

Agents can capture PNG screenshots of any named UI route from the command line without opening Xcode.

### How to take a screenshot

```bash
make ios-build              # build first (or skip if already built)
make ios-snapshot ROUTE=settings   # capture SettingsView
make ios-snapshot ROUTE=scan       # capture ScanView with fixture card images
make ios-snapshot-all              # capture all known routes
```

PNGs are written to `services/.artifacts/ui-snapshots/<route>.png` (gitignored).

Set `IOS_SNAPSHOT_WAIT=<seconds>` to override the per-route default settle wait (4s for most routes, 5s for `scan`).
Set `IOS_SNAPSHOT_SIMULATOR_ID=<udid>` to target a specific simulator.

### How it works

- `scripts/ios-screenshot.sh` boots a simulator (prefers any already-booted device), installs the built `.app`, launches it with a `-UI_PREVIEW_ROUTE <route>` argument, waits, captures via `xcrun simctl io screenshot`, and terminates the app.
- In `#if DEBUG` builds, `MTGScannerApp` reads the `UI_PREVIEW_ROUTE` UserDefaults key (set by the launch arg) and swaps `RootTabView` for `PreviewGalleryRootView(route:)`.
- Production builds are completely unaffected — the `#if DEBUG` guard ensures no preview code reaches release.

### Available routes

| Route | View | Notes |
|-------|------|-------|
| `card-detail` | `CardEditFixtureView` | Shared card detail with Edit action |
| `card-row-list` | `CardListPricingFixtureView` | Hold rows to review sample artwork, missing data, and native actions |
| `card-row-preview` | `CardListPricingFixtureView` | Foil preview with cached sample artwork |
| `copy-cards` / `copy-move` | `CardTransferFixtureView` | Copy task sheet, destination unset and confirmation disabled; `copy-move` aliases `copy-cards` |
| `move-cards` | `CardTransferFixtureView` | Move task sheet, chosen destination and partial quantities, confirmation enabled |
| `transfer-destinations` | `CardTransferFixtureView` | Production picker with many collections/decks, wrapping names, and excluded source lists |
| `transfer-destinations-empty` | `CardTransferFixtureView` | No eligible existing destinations; New Collection and New Deck remain available |
| `transfer-quantities` | `CardTransferFixtureView` | Production quantity review with 30 long-name rows, mixed finishes, and partial stacks |
| `transfer-error` | `CardTransferFixtureView` | Task sheet with a real stale-source transfer error seeded once |
| `pricing-results` | `CardListPricingFixtureView` | Totals with buying, zero, and unknown quantities |
| `pricing-collection` | `CardListPricingFixtureView` | Populated collection with totals |
| `pricing-deck` | `CardListPricingFixtureView` | Populated deck with quantities and totals |
| `selection-results` / `selection-collection` / `selection-deck` | `CardListPricingFixtureView` | 30-card lists in the production tab shell; for collections/decks, open Library and the list. Review the fixed title at rest and while scrolling in both modes; selection hides Back. Add Card is in More options |
| `undo-results` / `undo-collection` / `undo-deck` | `CardListPricingFixtureView` | Saved deletion with page-local Undo |
| `undo-empty` / `undo-bulk` | `CardListPricingFixtureView` | Last-row and bulk-delete undo |
| `undo-navigation` | `CardListPricingFixtureView` | Real tab navigation with a pending Results deletion |
| `pricing-filter` | `CardListPricingFixtureView` | CK buying toggle and Retail/Buylist price filters |
| `pricing-filter-editing` | `CardListPricingFixtureView` | Unformatted draft with focused field and Previous/Next/Done keyboard toolbar |
| `pricing-filter-invalid` | `CardListPricingFixtureView` | Invalid draft with inline error; completion stays focused until corrected |
| `pricing-large` | `CardListPricingFixtureView` | Large monetary totals for layout checks |
| `result-scan-artwork` | `ResultScanFixtureView` | Persisted result, artwork first; cached sample artwork |
| `result-scan-image` | `ResultScanFixtureView` | Persisted captured scan with full card bounds |
| `result-scan-zoom` | `ResultScanFixtureView` | Native scan viewer enlarged around collector number, with Close |
| `result-scan-edit` | `ResultScanFixtureView` | Result editor with Scan selected once |
| `result-scan-missing` | `ResultScanFixtureView` | Legacy result, editable with artwork only |
| `collection-scan-excluded` / `deck-scan-excluded` | `ResultScanFixtureView` | Destination details without scan controls |
| `card-edit` | `CardEditFixtureView` | Prefilled draft editor with Save/Cancel |
| `settings` | `SettingsView` | Full settings form with real `AppModel` |
| `scan-count-zero` / `scan-count-new` / `scan-count-overflow` | `ScanCountFixtureView` | Production tab shell on Settings: no badge with older Results, 12 newly scanned cards, or 1,000 cards displayed as 99+ |
| `scan-count-navigation` | `ScanCountFixtureView` | Open Results to clear 12; leave and simulate a new scan. Open Results button also checks programmatic navigation |
| `capture-table-binder` | `CaptureFixtureView` | Nine-pocket page, production Table tab and controls, fractional zoom |
| `capture-station-ready` / `capture-station-settling` / `capture-station-capturing` | `CaptureFixtureView` | Inert capture dependencies, real Station states |
| `capture-station-stopped` / `capture-station-error` / `capture-station-paused` | `CaptureFixtureView` | Explicit Start, capture retry, temporary zoom suspension with activity still started |
| `capture-recognition-foil` / `capture-recognition-disabled` | `CaptureFixtureView` | Foil completion notice or notification preference suppression |
| `capture-recognition-stack` / `capture-recognition-processing` | `CaptureFixtureView` | Three compact completion notices with three queued requests, or queued requests alone; production queue actions |
| `capture-zoom-open` / `capture-zoom-menu` | `CaptureFixtureView` | Fully exposed inline selector at 1.5×; former menu route is a compatibility alias |
| `capture-zoom-pinch-low` / `capture-zoom-pinch-high` / `capture-zoom-pinch-edge` / `capture-zoom-pinch-upper` | `CaptureFixtureView` | Station Ready after zoom at applied 1.9× / 2.1× / 1.99× / 3.2× (1.99× displays 1.9×) with the corresponding family centered |
| `capture-zoom-transition` / `capture-station-zoom-transition` | `CaptureFixtureView` | Fixture driver held at intermediate applied zoom, chosen destination displayed; shutter locked, active Stop available; another target interrupts and resumes detection |
| `capture-station-brightness` | `CaptureFixtureView` | Ready with the actual brightness popup open; opening alone has not paused Station |
| `capture-brightness` / `capture-brightness-adjusted` | `CaptureFixtureView` | Actual horizontal popover at 50% / 48% |
| `scan` | `FixtureCameraViewController` | Fixture card images + real detection overlay |
| `csv-import` | `CSVImportFixtureView` | Matched, ambiguous, and invalid rows; problems-first review |
| `csv-import-undo` | `CSVImportFixtureView` | Bulk skip feedback with Undo |
| `csv-import-ready` / `csv-import-skipped` | `CSVImportFixtureView` | All-ready and all-skipped reviews |
| `csv-import-loading` / `csv-import-error` / `csv-import-empty` | `CSVImportFixtureView` | Progress, file error, and file selection |
| `csv-import-large` / `csv-import-detail` | `CSVImportFixtureView` | Large matched list and unresolved row details |
| `list-operation` | `CardListOperationFixtureView` | Target-first list selection |
| `list-subtract` | `CardListOperationFixtureView` | Sale subtraction with quantity shortfalls |
| `list-add-delete` | `CardListOperationFixtureView` | Add quantities and delete tool preview |
| `list-operation-complete` | `CardListOperationFixtureView` | Saved operation with Undo |
| `csv-subtract` | `CardListOperationFixtureView` | CSV subtraction review |
| `list-deleted-collection` | `CardListOperationFixtureView` | Open collection safely handles tool deletion |
| `list-deleted-deck` | `CardListOperationFixtureView` | Open deck safely handles tool deletion |
| `collection-empty` | `CSVImportFixtureView` | Empty collection with CSV import entry point |
| `deck-empty` | `CSVImportFixtureView` | Empty deck with CSV import entry point |

### Adding a new route

1. Add a `case "<name>":` branch in `apps/ios/MTGScannerKit/Sources/MTGScannerFixtures/PreviewGalleryRootView.swift` returning the view.
2. Add a `#Preview` block for Xcode canvas support.
3. Add `"<name>"` to the `IOS_SNAPSHOT_ROUTES` variable in `Makefile` so `make ios-snapshot-all` includes it.
4. Run `make ios-snapshot ROUTE=<name>` to verify the PNG.
5. Document the new route in the table above.

### Capture fixture variants

The `capture-*` routes use `RootTabView`, `ScanView`, and the production controls,
with inert camera and recognition dependencies and an isolated in-memory store.
State is seeded after appearance/configuration. Completion notices use a 60-second fixture lifetime for inspection; production retains independent three-second expiry. The stack and processing routes keep three real requests queued with concurrency zero, so their queue actions remain interactive without network access. Inline zoom and brightness use the
real controls. Preset transition fixtures hold the elapsed-time fixture driver at an
intermediate applied value while presenting the destination. Selecting a different
anchor interrupts that hold.
Set `SIMCTL_CHILD_CAPTURE_FIXTURE_BACKGROUND=bright` before `make ios-snapshot`
for a bright photographic scene covering the entire viewfinder, including beneath
controls and native tab material; the default scene is dark. A complete aspect-fit
binder/card remains inset for edge inspection. This is synthetic layout evidence,
not a production camera crop or optical framing result. The `CaptureFixture` log
category records the runtime Reduce Motion, Reduce Transparency and Increase Contrast
flags for verification.
Use `xcrun simctl ui <udid> appearance light|dark` and
`xcrun simctl ui <udid> content_size large|accessibility-extra-extra-extra-large`
for appearance and text-size variants. The system Reduce Motion preference is honored.

### Camera routes and fixture frames

The Simulator has no camera. The `scan` route uses `FixtureCameraViewController`, which:
- Displays fixture card images from `Resources/FixtureFrames/` in a `UIImageView`.
- Feeds the same images as `CVPixelBuffer`s to the real `CardDetectionEngine`.
- Draws detection overlays using Vision's normalized coordinates mapped to the image bounds.
- Cycles through images on a timer (default: 5 Hz) — overlays appear within a few seconds.

Fixture code lives in the `MTGScannerFixtures` SPM target (`Sources/MTGScannerFixtures/`), which keeps debug assets out of release builds.

To add more fixture images: copy images to `apps/ios/MTGScannerKit/Sources/MTGScannerFixtures/Resources/FixtureFrames/` and add the filename (without extension) to `FixtureFrameSource.fixtureNames`.
