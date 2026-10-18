# Capture experience: findings and rework requirements

Date: 2026-10-18. Status: findings and requirements for the next design pass;
not an approved replacement visual design or an implementation-completion report.

## Purpose

Improve the Table and Station capture experience after the user rejected the
implemented visual treatment. Preserve useful functional work while reconsidering
the control composition, zoom presentation, and background treatment together.
The target is a compact, attractive, deliberate native iPhone interface with the
camera image as the primary content. More decoration is not itself the solution.

Companion instructions: [Impeccable workflow rework](impeccable-feature-workflow-rework.md).

## Evidence and what went wrong

The user described the result as unpolished, basic, and unsatisfying after multiple
iterations. Their 2026-10-18 screenshot shows a large open zoom menu with four short
numeric labels and substantial unused space to their right, above a heavy dark
control area. They reported that the revised gradient was different but not better,
with an abrupt transition between the gradient and the dark area behind controls.

The screenshot is locally available at
`/Users/brettvitaz/Downloads/Screenshot 2026-10-18 at 10.27.31.png`.
This external file is not bundled with this document. Preserve or reattach it to
the next visual-review packet; do not assume a new checkout contains it.

The preceding implementation addressed the closed zoom button's intrinsic width.
That did not address the open popup the user was criticizing. Tests and screenshots
were collected, but the oversized open popup was not treated as a failed outcome.
Likewise, changing gradient stops did not establish that the full composition
worked. These are review failures, not evidence that more small patches will help.

Verified source anchors as of this document:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift:240`
  still passes `.automatic` for Station and `.standard` for Table.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/AutoScanCamera.swift:7`
  selects ultra-wide for automatic mode when close-up capability is available;
  otherwise it selects wide-angle.
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ZoomPresetControl.swift:29`
  sizes the closed button using intrinsic content size. The `UIMenu` is constructed
  at line 51. Closed-button sizing is not proof of open-menu compactness.

Local implementation records are in `tmp/capture-spacing/handoff.md` and
`tmp/capture-spacing/comparison.html`. They are gitignored historical evidence,
not visual approval. Refresh source anchors before implementation.

## Settled requirements

### 1. Use the same camera selection in both modes

The user's later instruction was: “I think we need to make the modes use the same
camera lens.” This supersedes the older brief's instruction to preserve separate
mode-specific lens selection. Do not ask the user to decide again whether the
modes should share a lens.

Both modes must use the same physical-camera selection policy on a given device,
including capability fallback and the meaning of the displayed zoom baseline.
Switching modes at the same baseline must not change the view because one mode
chooses a different lens. Preserve the existing reset/pause safety semantics unless
the user explicitly changes them; distinguish an intentional zoom reset from an
unexpected lens or preview-crop change.

The exact common policy remains an engineering choice to validate. Review
[ADR 0007](../decisions/adr-0007-auto-scan-focus-and-close-up-camera.md): close-up
focus work solved a real Station problem. Validate that behavior alongside Table's
binder framing and detail before selecting the common policy. Neither blindly
forcing wide-angle nor blindly forcing ultra-wide is an accepted solution.

Keep continuous focus, supported-device fallback, the existing processing pipeline,
highest configured still-photo dimensions, and complete crops. Do not add a lens
selector as a substitute for consistent defaults. Record the replacement camera
decision and supersede the conflicting portion of ADR 0007 when implementing it.
The shared policy is currently unimplemented; this document does not fix it.

### 2. Make the open zoom selector compact

Retain presets 1×, 1.5×, 2×, and 3×; pinch zoom; selected-state feedback; and the
actual applied/clamped zoom label. Use the same location and behavior in both modes.

The open selector must feel proportionate to four short choices, with deliberate
alignment and trailing spacing. Review the open state at actual device size.
Changing only the closed button does not satisfy this requirement.

Evaluate an appropriate native presentation first. If the system menu cannot meet
the required compactness, present a native-feeling alternative during design and
approve its interaction and appearance before replacing the component. The older
brief's choice of a native menu is open for reconsideration; no particular custom
replacement, dimensions, or layout has been approved yet. Preserve accessible
selection, dismissal, Dynamic Type, and minimum touch targets.

### 3. Design the gradient and control background as one composition

The camera image, contrast treatment behind controls, lower safe area, and native
tab bar must form a coherent transition. Avoid an apparent seam, abrupt dark band,
or excessive opaque area that consumes useful framing space. Establish the whole
background treatment before adjusting isolated gradient stops.

Evaluate bright and dark camera scenes, including a bright tabletop. Keep controls
legible and preserve full binder-page visibility. The user has not approved exact
gradient stops, opacity values, material, or a replacement background treatment.

### 4. Make the complete surface feel deliberate

Retain the minimalist capture goal while improving hierarchy, alignment, spacing,
proportion, and restraint. Review zoom, shutter, thumbnail, import or Start/Stop,
torch, Station status, and tab bar as one screen. A collection of individually
acceptable controls is not sufficient evidence of a polished composition.

Use native typography, symbols, touch targets, navigation, and accessibility.
Visual interest should support scanning and immediate feedback. Do not introduce
large decorative panels or extra controls to demonstrate design effort.

## Functional work to preserve

The original brief remains the baseline for unaffected behavior. Its camera-policy
constraint is superseded as described above; its popup component choice needs
reconsideration. Preserve these product decisions during visual exploration:

- Five native destinations: Table, Station, Results, Library, Settings.
- Consistent control slots; centered manual shutter; explicit Station Start/Stop.
- Compact, truthful Station states: Ready, Settling, Capturing, Stopped, Paused.
  Capturing and readiness transitions must remain visible without repeated helper text.
- Safe zoom: actual changes pause watching/settling once and require Start;
  opening a selector alone does not pause; accepted captures reject zoom changes.
- One compact recognition toast, foil feedback, notification preference, and
  preserved results, queue actions, and announcement priority. The user explicitly
  liked the toast feedback; do not redesign it away.
- Single torch button: tap toggle, hold brightness, explicit accessible entry;
  horizontal brightness popup, top percentage, repeatable preset taps, relative
  1% dragging, no initial jump or release snap, one preset haptic and no drag haptics.
- Complete binder edges, readable card detail, and usable Station images at low,
  middle, and high stack positions. The reference Station distance was 125–175 mm,
  not a universal hardcoded camera distance.

## Next design pass and acceptance evidence

Follow Impeccable's installed shaping and native iOS guidance. Treat the rejected
capture composition as evidence, not as a visual treatment that must be preserved.
Explore whole-screen alternatives through its applicable concept process, then
record the user's selected direction. Existing functional decisions need no repeat
interview. An HTML sketch can communicate intent but cannot approve native menu
sizing, safe areas, materials, or hardware camera behavior.

Before production styling, establish native feasibility for the zoom presentation
and full camera/control/tab-bar composition. Carry the selected direction, reference
images, spacing and sizing decisions, and interaction states into the build handoff.

| Concern | Required evidence |
| --- | --- |
| Shared camera | Production selection tests for close-up-capable and fallback devices; hardware captures/logs identifying the selected lens in both modes. |
| Matching view | Fixed-position mode-switch comparison at equivalent applied zoom; inspect lens, preview crop/aspect fill, and any intentional reset separately. |
| Capture quality | Full binder page with readable card detail; low/middle/high Station stacks; full images and crops inspected at native resolution. |
| Zoom compactness | Real open selector screenshots and selection/dismissal interaction in both modes; no substitute closed-button test. |
| Background transition | Full-screen bright/dark camera fixtures, selector open and closed, with safe area and tab bar visible. |
| Native fit | Supported iOS 18 and 26; smallest supported iPhone and iPad; light/dark appearance and accessibility text. |
| Feedback and safety | Real Station state transitions, safe zoom, recognition toast and torch interaction regression coverage. |
| Visual quality | Independent finish review against the selected direction and the user's rejection screenshot. |

Simulator evidence cannot prove optical focus, physical sharpness, real torch feel,
or haptics. Mark outstanding hardware checks explicitly. Separate behavioral test
results, visual-review verdict, and physical acceptance in the handoff.

## Boundaries

This document captures findings and current requirements. It does not approve a
new visual concept, claim the lens is unified, or authorize unrelated recognition,
backend, navigation, or collection changes. The next approved build brief should
incorporate these requirements and replace conflicting older instructions instead
of appending another ambiguous note to them.
