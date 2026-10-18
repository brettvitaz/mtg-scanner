---
version: 1
slug: "tgscannerkit-features-scan-scanview-swift-04ac68f7"
primary_target: "apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift"
related_targets: ["apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ZoomPresetControl.swift","apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanView.swift"]
---

# Capture — Table and Station
Mode: Operate. Approved replacement, native/code-led.
Authority: tmp/feature-briefs/capture-rework.md; user camera references and selected-direction-v1 storyboard in tmp/design/capture-rework/.

## Direction contract
THESIS: Keep collectors inside the continuous viewfinder while framing binder pages and feeding Station. Remove the rejected menu and enclosing black lower control region.

OWN-WORLD: Native SF text and symbols, white shutter, local dark system materials, restrained system-yellow active zoom. Camera scenery remains visible between controls and under native tabs in bright rooms and dim stand lighting.

STORY: Frame, choose magnification, capture; Station pauses before actual zoom movement and explicitly starts again. Recognition confirms once at the top; Station status remains beside its action.

FIRST VIEWPORT: Full-bleed camera; active 56 pt zoom circle centered above a 76 pt shutter with 24 pt clear separation. Inactive numerals move at 52 pt spacing. Thumbnail left, import or Start/Stop right; Station status below Start/Stop. Torch moves above the rail on narrow layouts; accessibility choices wrap. Native five-tab shell remains.

FORM: User-pinned fluid native viewfinder, selected direction v1; no new concept round or seed (approved brief explicitly forbids reopening selection). Signature: interruptible optical preset easing, continuous pinch and centered family recentering.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Quality bar
Camera references establish fluidity/material quality, not literal Camera controls. Native checkpoint must prove complete-screen fit and actual interactive selector. Unit tests, simulator rendering, independent finish review and physical optics each have separate verdicts. No hardware sharpness claims from simulator output.
