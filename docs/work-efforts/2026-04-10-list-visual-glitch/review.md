# Review: Library list visual glitch

**Reviewed by:** Ori
**Date:** 2026-04-10

## Summary

**Verdict:** pass, with the final scope narrowed to Library list surfaces and the Results sticky count explicitly preserved.

**What was requested:** Fix the unwanted rounded-row behavior on the relevant Library list surfaces while keeping the Results sticky scanned-card count behavior.

**What was delivered:**
- `LibraryView.swift` now uses `.plain` list styling, explicit section header views, and row-level swipe actions while preserving rename/create behavior.
- `CollectionDetailView.swift` and `DeckDetailView.swift` now match the non-rounded list treatment by using `.plain` list styling and explicit header background treatment.
- `ResultsView.swift` keeps the sticky scanned-card count behavior after temporary exploratory changes were reverted.

**Assessment:** The final patch is smaller and cleaner than the exploratory/debugging branch state. The main useful findings were: (1) the visible affected list was not only the top-level `LibraryView`, (2) the detail-view list path mattered, and (3) the sticky Results count was preferred, so Results restructuring was not part of the final fix. The remaining code is narrowly focused on the Library surfaces involved in the glitch.

## Code Review Checklist

### 1. Correctness

**Result:** pass

The final patch is aligned with the user-validated behavior and preserves the preferred sticky Results count behavior.

### 2. Simplicity

**Result:** pass

The final diff removes diagnostic noise and keeps only the Library/detail-view list changes that support the chosen behavior.

### 3. No Scope Creep

**Result:** pass

Temporary debug changes, SwiftLint config edits, version-bump noise, and experimental Results restructuring were removed from the final patch.

### 4. Tests

**Result:** pass

No automated UI test was added, but the work was repeatedly verified through successful iOS builds and explicit on-device install/launch cycles against Brett’s phone.

### 5. Safety

**Result:** pass

The change is UI-only, preserves existing delete/rename flows, and does not alter app data models, threading, or API behavior.

### 6. API Contract

**Result:** not applicable

No API or schema behavior changed.

### 7. Artifacts and Observability

**Result:** not applicable

The change does not touch recognition, detection, or debug artifact generation.

### 8. Static Analysis

**Result:** pass with known repo-wide exceptions

The branch builds successfully. Repo-wide lint issues remain pre-existing and outside the scope of this task.

## Verification Results

- `xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner -destination 'name=Brett’s iPhone' build` passed repeatedly during the final cleanup cycle.
- Explicit `xcrun devicectl device install app ...` succeeded for Brett’s phone.
- Explicit `xcrun devicectl device process launch ...` succeeded for Brett’s phone.
- Device verification used explicit `devicectl` install/launch rather than trusting `xcodebuild install`.
- Temporary Results-page restructuring was verified, then reverted after Brett confirmed the sticky scanned-card count should remain.

## Notes

- Early branch iterations contained useful diagnostics but also substantial temporary noise. The final review is based on the cleaned branch state, not the intermediate debugging states.
- The `CoreDeviceError Code=1002 "No provider was found."` warning remained noisy during device operations, but install and launch still succeeded and were treated as non-blocking for this workflow.
