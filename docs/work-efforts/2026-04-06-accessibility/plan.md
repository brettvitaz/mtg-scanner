# Plan: Improve iOS accessibility best practices

**Planned by:** Codex
**Date:** 2026-04-06

## Approach

Apply a practical accessibility pass across the existing SwiftUI iOS app without introducing new UI test infrastructure. Prioritize custom controls and shared components because they affect the highest number of screens. Preserve existing behavior while adding VoiceOver semantics, selected-state values, reduce-motion support, and better announcements for transient status.

## Implementation Steps

1. Add scan and auto-scan accessibility semantics: label capture, photo picker, flashlight, zoom presets, auto-scan status, recognition badges, and hide the camera preview from VoiceOver.
2. Improve transient scan toasts: move toast views out of `ScanView`, announce recognized cards, expose the card summary, and keep the dismiss button reachable.
3. Improve shared list and toolbar semantics: combine card row summaries, hide decorative thumbnails/icons, label export/sort/filter/close/add buttons, and expose move/copy destination counts.
4. Improve filter controls: announce selected state for rarity, color identity, set, and type filters and hide purely visual checkmarks.
5. Improve card detail, correction, fullscreen image, and settings semantics: label card images, badges, prices, stats, saved/added banners, text fields, and sliders.
6. Add focused unit coverage for the shared card-row accessibility summary.
7. Verify with lint, app test/build command, and whitespace checks.

Steps are sequential because later shared-component checks depend on the first pass compiling cleanly.

## Files to Modify

| File | Change |
|------|--------|
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/*` | Add scan-control labels, values, reduce-motion support, camera preview hiding, and accessible toast handling |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanView.swift` | Add auto-scan status and start/stop semantics |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/*` | Add shared row summaries, filter/sort labels, destination labels, and recognition badge values |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Results/ResultsView.swift` | Add export/selection labels and keep price-fetch helper refactor lint-compliant |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/*` | Add toolbar and row labels for collections and decks |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetail/*` | Add card image, badge, price, stats, toast, and fullscreen image semantics |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Correction/CorrectionView.swift` | Add text-field, confidence, and saved-banner accessibility |
| `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Settings/SettingsView.swift` | Add explicit slider labels and values |
| `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/AccessibilitySummaryTests.swift` | Add focused coverage for card row accessibility summary text |

## Risks and Open Questions

- SwiftUI container modifiers can accidentally hide nested controls from VoiceOver. Verify that transient toast dismiss controls remain reachable.
- The configured `make ios-test` scheme currently reports `Executed 0 tests`; use it as a build/test smoke check, not proof that the Swift package tests are executing.
- Direct `swift test` is not expected to work for this iOS-only package from this environment because SwiftPM tries to build for macOS and fails on `UIKit`.

## Verification Plan

- `make ios-lint`
- `make ios-test`
- `git diff --check`
- Manual VoiceOver and Dynamic Type pass before release or merge if device/simulator QA time is available.
