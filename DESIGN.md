---
name: MTG Scanner capture
description: A fluid native viewfinder for Table and Station.
colors:
  selected-zoom: "yellow"
  control-foreground: "white"
  feedback-backing: "rgb(0 0 0 / 65%)"
  disabled-shutter: "rgb(255 255 255 / 40%)"
typography:
  active-zoom:
    fontFamily: "-apple-system"
    fontWeight: 600
  inactive-zoom:
    fontFamily: "-apple-system"
    fontWeight: 500
  station-action:
    fontFamily: "-apple-system"
    fontSize: "20pt"
    fontWeight: 500
  station-status:
    fontFamily: "-apple-system"
    fontWeight: 600
rounded:
  recovery: "16pt"
  thumbnail: "4pt"
spacing:
  control-gap: "24pt"
  horizontal-inset: "20pt"
  bottom-inset: "24pt"
  status-gap: "8pt"
components:
  shutter:
    textColor: "{colors.control-foreground}"
    size: "76pt"
  shutter-disabled:
    backgroundColor: "{colors.disabled-shutter}"
  zoom-selected:
    textColor: "{colors.selected-zoom}"
    typography: "{typography.active-zoom}"
  station-action:
    textColor: "{colors.control-foreground}"
    typography: "{typography.station-action}"
    size: "48pt"
  station-status:
    backgroundColor: "{colors.feedback-backing}"
    textColor: "{colors.control-foreground}"
    typography: "{typography.station-status}"
    padding: "4pt 8pt"
  capture-recovery:
    backgroundColor: "{colors.feedback-backing}"
    textColor: "{colors.control-foreground}"
    rounded: "{rounded.recovery}"
    padding: "8pt 12pt"
---

# Design System: MTG Scanner capture

## Overview

**Creative North Star: "Fluid native viewfinder"**

Table and Station keep collectors inside the camera image. Independent controls float over the scene: the white shutter leads, selected magnification uses restrained system yellow, and local dark material supports secondary actions. The result is clean, fast and confident, consistent with PRODUCT.md's precision reference tool.

This record covers the implemented capture surfaces only. It does not establish a design system for Results, Library or Settings. The approved capture brief and surface contract supply the language; the SwiftUI implementation supplies the tokens. The latest human corrections supersede the earlier contrast-only verdict and its selected zoom backing. This record reflects current source; it does not assign a new finish-review verdict. Both modes now request the same automatic camera policy. Physical camera acceptance, VoiceOver focus continuity and Reduce Transparency verification remain separate outstanding checks.

**Key Characteristics:**
- Continuous camera imagery between independent controls.
- A centered shutter and active zoom axis, with stable secondary capture slots.
- Native semantic text, SF Symbols and local dark system materials.
- Truthful magnification and Station status, with restrained state motion.

## Colors

A compact native camera palette gives the shutter priority and reserves yellow for selected magnification.

### Primary
- **Selected Zoom:** SwiftUI `Color.yellow`, scoped to the active zoom value. The frontmatter's CSS-compatible name preserves the native color name, not a fixed sRGB measurement. Native rendering remains authoritative; do not substitute CSS yellow or a sampled screenshot hex into production.

### Neutral
- **Control Foreground:** SwiftUI white on the shutter, inactive zoom, Station actions and status.
- **Feedback Backing:** black with source opacity on Station status and capture-recovery surfaces; selected zoom uses the same local native material as the flashlight without an additional black overlay.
- **Disabled Shutter:** translucent white fill communicates temporary unavailability while retaining the outer ring.

**The Local Contrast Rule.** Back operational text with local contrast where camera detail can compete with it; preserve visible image between independent controls.

## Typography

**Body and Label Font:** the native SwiftUI system family (SF on iOS). No custom display face is established by this capture system.

### Hierarchy
- **Active zoom:** `.subheadline.weight(.semibold)`, with monospaced digits.
- **Inactive zoom:** `.subheadline.weight(.medium)`, with monospaced digits.
- **Station action:** a medium-weight 20-point SF Symbol, using `play.fill` or `stop.fill`, with an accessible Start/Stop label.
- **Station status:** `.caption.weight(.semibold)` with a state symbol.
- **Recovery and zoom retry:** `.caption`.

Zoom and status use semantic styles for Dynamic Type; the secondary action symbols retain their fixed source size. Frontmatter omits fixed font sizes and line heights for semantic text. The scaled metrics in the sidecar describe layout tied to these native styles.

**The Applied Value Rule.** Pinch text follows the actual factor and unrounded family, capping rounded labels at 1.9× and 2.9× before the next family. During a preset move, the selected destination is presented directly; intermediate applied factors remain authoritative for camera safety and interruption.

## Layout

The camera preview ignores safe areas. Capture controls form a centered cluster bounded to a native width of 420 points with the frontmatter insets; they do not create a full-width enclosing toolbar. The active zoom stays on the shutter axis, with the shared control gap below the framing rail. Ordinary inactive zoom anchors move horizontally at 52-point intervals around the selected family. The shared control gap also separates the shutter row from the native navigation boundary.

The bottom row centers the shutter independently of its fixed 48-point side slots: last-card thumbnail left, Table import or Station Start/Stop right. Status sits centered above framing in an independent strip with a 20-point minimum height scaled relative to `.caption`; Table reserves the same space invisibly and hides it from accessibility. The status gap separates this strip from framing, so text never moves the action. At accessibility text sizes zoom neighbors move to a separate row below the active pill. Torch lifts to its own row when available control width is below 360 points or accessibility text is active. These are native available-width rules, not browser breakpoints.

The existing native five-destination tab shell remains the navigation boundary. Recognition confirmation stays at the top; capture recovery stays near capture controls and remains distinct from recognition-queue failures.

## Elevation & Depth

SwiftUI `.ultraThinMaterial` in a local dark color environment gives the controls depth without a broad lower blackout. Selected zoom uses the same material helper as the flashlight. Station status and capture recovery combine the same local material with black backing. Native tab material belongs to navigation rather than a custom capture panel.

Four zero-radius black shadows at horizontal and vertical offsets of one point form a crisp outline on zoom numerals, preserving their edges over bright imagery. Station status uses a compact backed capsule. Sidecar extensions preserve their source values. System material is a semantic native primitive, not a fabricated CSS blur or flat color token.

## Shapes

Circles distinguish the shutter, import and Station Start/Stop controls; capsules carry selected zoom, Station status and zoom retry. The shutter uses a 76-point outer circle with a 4-point white stroke and a 64-point inner fill. Zoom controls share a 44-point minimum target baseline, with row height `max(44, scaledSubheadlineLineHeight + 12)` from a 20-point line-height metric. Text keeps its intrinsic size with 4-point horizontal padding, allowing the selected capsule to expand at accessibility sizes. Import and Station action share 48-point circles. Recovery uses the rounded frontmatter shape; the thumbnail retains a small corner radius and a 36-by-48-point aspect-fit frame.

## Components

### Capture shutter

The strongest control is a white ring and fill on local dark material. Disabled state reduces the inner fill opacity. A pressed spring scales the shutter unless Reduce Motion is enabled. It retains its centered slot when zoom families change.

### Inline zoom anchors

Three always-exposed anchors represent the 1×, 2× and 3× families. The active capsule displays actual pinch zoom or the chosen preset destination during preset movement; inactive labels display their bases. An exact base toggles to its half-step; other values return to base. The active family recenters with a smooth transition unless Reduce Motion is enabled. Accessibility names the family, reports the value and supplies direct base/half-step actions and adjustment. These factor labels do not identify physical lenses or focal lengths. Both capture modes request the same automatic camera policy; the shared request does not establish optical quality acceptance.

### Station action and status

Start/Stop is a fixed circle with a play/stop symbol. Compact symbol-plus-text status occupies the independent strip above framing in a capsule with 8-point horizontal and 4-point vertical padding, black feedback backing and shared dark material. Start is unavailable during zoom motion; Stop stays available. Status derives from operational state, and completion can trigger a nonrepeating symbol bounce unless Reduce Motion is enabled. The label and symbol keep state understandable without depending on color alone.

### Capture recovery

A multiline, locally backed recovery button provides a capture retry target with a minimum height of 44 points. This belongs near capture controls; queue failure remains independently actionable.

### Secondary capture slots

The aspect-fit last-card thumbnail and circular native photo-import action balance the shutter. Torch retains its existing toggle/hold and horizontal brightness interaction through the shared framing layout. This document does not redefine those preserved interactions or introduce a second brightness indicator.

## Do's and Don'ts

### Do:
- **Do** keep the camera image visible between independent capture controls.
- **Do** use native semantic text and dark system material in capture components.
- **Do** preserve the centered active zoom and shutter axis through family changes.
- **Do** pair Station state text with its native symbol and keep capture recovery distinct from queue recovery.

### Don't:
- **Don't** restore the rejected zoom dropdown or an enclosing opaque lower control band.
- **Don't** count through intermediate applied factors during a preset move or label magnification as a focal length or physical lens.
- **Don't** treat sampled colors, fixture scenery or schematic storyboard fills as production palette tokens.
- **Don't** infer physical camera quality or complete accessibility acceptance from simulator presentation.
