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

STORY: Frame, choose magnification, capture; Station pauses before actual zoom movement and explicitly starts again. Recognition confirms once at the top; Station status occupies an independent strip above framing.

FIRST VIEWPORT: Full-bleed camera; active flashlight-sized 44pt zoom surface centered above a 76pt shutter with 24pt clear separation; smaller semantic labels and intrinsic text expansion at AX. Inactive numerals move at 52pt spacing. Thumbnail left; equal 48pt import or Start/Stop surfaces share a fixed trailing slot. Station status is independent of action sizing, in a centered reserved feedback strip above framing, leaving equal 24pt zoom/shutter/navigation edge gaps. Torch moves above the rail on narrow layouts; accessibility choices wrap. Native five-tab shell remains.

FORM: User-pinned fluid native viewfinder, selected direction v1; no new concept round or seed (approved brief explicitly forbids reopening selection). Signature: interruptible optical preset easing, continuous pinch and centered family recentering.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Quality bar
Camera references establish fluidity/material quality, not literal Camera controls. Native checkpoint must prove complete-screen fit and actual interactive selector. Unit tests, simulator rendering, independent finish review and physical optics each have separate verdicts. No hardware sharpness claims from simulator output.

## Human correction authority
Latest user findings and C1–C11 in tmp/capture-refinement/corrections.md override prior metric/material/preset-readout promises. Reuse flashlight material exactly rather than selected-only black backing. Preset intent recenters once without counting intermediate values; actual camera factor remains the source for safety, pinch and completion. Both modes use the same close-focus-capable policy and fallback; physical optics remain a separate hardware check. New full finish review must read these human corrections as primary evidence against the prior scoped verdict.
