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

STORY: Frame, choose magnification, capture; an active Station suspends detection events during actual zoom movement, stays active with Stop available, waits 0.75 seconds after the last zoom movement, then rebaselines and resumes. Navigation and explicitly stopped Station still require Start. Up to three brief recognition completions stack independently at the top; aggregate queue progress and recovery actions stay with the latest-capture thumbnail; Station status occupies an independent strip above framing.

FIRST VIEWPORT: Full-bleed camera; active flashlight-sized 44pt zoom surface centered above a 76pt shutter with 24pt clear separation; smaller semantic labels and intrinsic text expansion at AX. Inactive numerals move at 52pt spacing. Thumbnail left; equal 48pt import or Start/Stop surfaces share a fixed trailing slot. Station status is independent of action sizing, in a centered reserved feedback strip above framing, leaving equal 24pt zoom/shutter/navigation edge gaps. Torch moves above the rail on narrow layouts; accessibility choices wrap. Native five-tab shell remains.

FORM: User-pinned fluid native viewfinder, selected direction v1; no new concept round or seed (approved brief explicitly forbids reopening selection). Signature: interruptible optical preset easing, continuous pinch and centered family recentering.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Quality bar
Camera references establish fluidity/material quality, not literal Camera controls. Native checkpoint must prove complete-screen fit and actual interactive selector. Unit tests, simulator rendering, independent finish review and physical optics each have separate verdicts. No hardware sharpness claims from simulator output.

## Human correction authority
Latest user findings and C1–C11 in tmp/capture-refinement/corrections.md override prior metric/material/preset-readout promises. Reuse flashlight material exactly rather than selected-only black backing. Preset intent recenters once without counting intermediate values; actual camera factor remains the source for safety, pinch and completion. Both modes use the same close-focus-capable policy and fallback; physical optics remain a separate hardware check. New full finish review must read these human corrections as primary evidence against the prior scoped verdict.

## Latest lifecycle correction authority
L1–L4 in tmp/capture-lifecycle/requirements.md and the latest capture-rework brief amendment supersede navigation resets to 1× and explicit Start after zoom. Each mode independently saves its applied zoom and restores it on navigation return. A single movable preview layer follows the visible capture mode, with a warm session during Table–Station handoff. Active Station suppresses detection events during motion and discards stale tracking results before automatic rebaseline/resume; accepted-photo protection and explicit Stop/navigation semantics remain.

Preview-only reframing for iPhone 17 Pro remains investigation, with the full photo preserved. No new framing-control system or sensor offset is established. Tokens, materials and geometry are unchanged. The physical iPhone 17 Pro live-preview test passed repeated capture-mode handoffs. Preview rendering and visible ownership are verified; optical image quality remains a separate acceptance check.

## Recognition feedback correction authority

User approved thumbnail-grouped aggregate queue progress, explicitly labeled queue actions, and independent top completion notices; then selected THREE notices and a brief subtle foil shimmer. Notices have no visible close controls, expire independently after three seconds, and retain only the newest three. At accessibility text sizes one readable notice remains, with queue actions in a reserved full-width row. Reduced Motion disables the single 0.8-second foil pass and notice transitions. The latest image is not a per-job progress proxy. Capture controls and queue position do not respond to notice height. Reframing remains proposal-only.

## Navigation color and trigger recovery authority

All five destinations use one blue selected icon/label accent through the native tab presentation bridge. Yellow remains the selected magnification color inside the camera. Native tab selection geometry and labels retain non-color selection cues. Active Station retains its 0.75-second post-zoom quiet window and fresh baseline. The experimental adjacent-frame gate and global translation veto are withdrawn: real low image noise could block valid arrivals after the burst state already settled. Station now shows Preparing during its existing warmup, then Ready after learning normal scene variation. Low-pass image resampling avoids coarse-grid aliasing without an added waiting period. Stability participates in burst settlement; next-reference learning overlaps photo/crop work without a fixed per-card wait. Stop and manual capture remain available during Preparing. Recorded-scene replay and the amended physical 1.5× Start/tap/rapid-drop/identical-copy/empty-tray workflow pass. Small-sample timing is acceptable to the user, without a claim of unchanged throughput or universal stand reliability. Three notices, subtle shimmer and proposal-only reframing remain.
