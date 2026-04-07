# Request: Improve iOS accessibility best practices

**Date:** 2026-04-06
**Author:** User

## Goal

Make the iOS app more accessible and compatible with common accessibility best practices. Focus on practical app-wide improvements for VoiceOver, custom controls, non-color-only state, reduce motion, and Dynamic Type resilience rather than a formal WCAG audit package.

## Requirements

1. Add meaningful VoiceOver labels, values, hints, and traits to custom scan, results, library, detail, filter, and settings controls.
2. Hide decorative images, camera preview layers, and purely visual icons from VoiceOver when they do not provide actionable information.
3. Keep actionable controls reachable, including custom overlay buttons and transient toast dismissal.
4. Expose selected and active states for scan mode, zoom presets, filters, sort state, auto-scan state, and status badges.
5. Respect reduce-motion for custom nonessential animations where practical.
6. Add lightweight automated coverage for pure accessibility helper behavior without adding a new UI test target.

## Scope

**In scope:**
- SwiftUI accessibility modifiers and helper text across the iOS app.
- Scan and auto-scan overlays, card rows, toolbar icon buttons, filters, move/copy sheets, card detail, correction, settings, and transient toasts.
- A small unit test for pure accessibility summary behavior.

**Out of scope:**
- Formal WCAG 2.2 AA certification or audit artifacts.
- New XCUITest target or ViewInspector dependency.
- Backend changes.
- Major visual redesign.

## Verification

- `make ios-lint` passes.
- `make ios-test` passes.
- `git diff --check` passes.
- Manual follow-up recommended: navigate the scan, results, card detail, correction, library, filters, settings, and move/copy flows with VoiceOver and large Dynamic Type enabled.

## Context

Files and areas to inspect before starting:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Results/ResultsView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Library/`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetail/`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Settings/SettingsView.swift`

## Notes

The repo already had a few accessibility annotations, but coverage was sparse and custom visual controls needed explicit VoiceOver semantics.
