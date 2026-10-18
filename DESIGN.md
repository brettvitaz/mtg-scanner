---
name: MTG Scanner capture
description: A fluid native viewfinder for Table and Station.
colors:
  selected-zoom: "yellow"
  control-foreground: "white"
  local-backing: "rgb(0 0 0 / 65%)"
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
    fontWeight: 600
  station-status:
    fontFamily: "-apple-system"
    fontWeight: 600
rounded:
  recovery: "16pt"
  thumbnail: "4pt"
spacing:
  control-gap: "24pt"
  horizontal-inset: "20pt"
  bottom-inset: "16pt"
  status-gap: "6pt"
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
    padding: "0pt 14pt"
  capture-recovery:
    backgroundColor: "{colors.local-backing}"
    textColor: "{colors.control-foreground}"
    rounded: "{rounded.recovery}"
    padding: "8pt 12pt"
---

# Design System: MTG Scanner capture

## Overview

**Creative North Star: "Fluid native viewfinder"**

Table and Station keep collectors inside the camera image. Independent controls float over the scene: the white shutter leads, selected magnification uses restrained system yellow, and local dark material supports secondary actions. The result is clean, fast and confident, consistent with PRODUCT.md's precision reference tool.

This record covers the implemented capture surfaces only. It does not establish a design system for Results, Library or Settings. The approved capture brief and surface contract supply the language; the SwiftUI implementation supplies the tokens. Native simulator review resolved two local contrast defects, with a ship verdict limited to those fixes. Physical camera acceptance, common lens policy, VoiceOver focus continuity and Reduce Transparency verification remain outstanding.

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
- **Local Backing:** black with source opacity on the active zoom circle and capture-recovery surface; it protects text against bright photographed detail.
- **Disabled Shutter:** translucent white fill communicates temporary unavailability while retaining the outer ring.

**The Local Contrast Rule.** Back operational text with local contrast where camera detail can compete with it; preserve visible image between independent controls.

## Typography

**Body and Label Font:** the native SwiftUI system family (SF on iOS). No custom display face is established by this capture system.

### Hierarchy
- **Active zoom:** `.title3.weight(.semibold)`, with monospaced digits.
- **Inactive zoom:** `.subheadline.weight(.medium)`, with monospaced digits.
- **Station action:** `.subheadline.weight(.semibold)`.
- **Station status:** `.caption.weight(.semibold)` with a state symbol.
- **Recovery and zoom retry:** `.caption`.

Semantic styles, rather than fixed font sizes, own Dynamic Type. Frontmatter intentionally omits fixed font sizes and line heights. The scaled metrics in the sidecar describe layout tied to these native styles.

**The Applied Value Rule.** Zoom text reports the applied factor, rounded for display only; family selection uses its unrounded value.

## Layout

The camera preview ignores safe areas. Capture controls form a centered cluster bounded to a native width of 420 points with the frontmatter insets; they do not create a full-width enclosing toolbar. The active zoom stays on the shutter axis, with the shared control gap below the framing rail. Ordinary inactive zoom anchors move horizontally at 52-point intervals around the selected family.

The bottom row uses balanced flexible side slots: last-card thumbnail left, shutter center, Table import or Station Start/Stop right. Station status sits below its action. At accessibility text sizes Station puts its action and status on separate rows below the shutter; zoom neighbors move to a separate row below the active circle. Torch lifts to its own row when available control width is below 360 points or accessibility text is active. These are native available-width rules, not browser breakpoints.

The existing native five-destination tab shell remains the navigation boundary. Recognition confirmation stays at the top; capture recovery stays near capture controls and remains distinct from recognition-queue failures.

## Elevation & Depth

SwiftUI `.ultraThinMaterial` in a local dark color environment gives the controls depth without a broad lower blackout. The active zoom also has black contrast backing. Capture recovery combines the same local material with black backing. Native tab material belongs to navigation rather than a custom capture panel.

Small black text shadows support zoom and Station status; they supplement backing rather than replace it. Sidecar extensions preserve their source values. System material is a semantic native primitive, not a fabricated CSS blur or flat color token.

## Shapes

Circles distinguish the shutter, selected zoom and import control; capsules carry Start/Stop and zoom retry. The shutter uses a 76-point outer circle with a 4-point white stroke and a 64-point inner fill. Selected zoom starts from a 56-point metric scaled relative to `.title3`; its circle follows text scaling. Inactive controls retain at least a 44-point target. Import is a 48-point circle, and Station action has minimum dimensions of 64 by 48 points. Recovery uses the rounded frontmatter shape; the thumbnail retains a small corner radius and a 36-by-48-point aspect-fit frame.

## Components

### Capture shutter

The strongest control is a white ring and fill on local dark material. Disabled state reduces the inner fill opacity. A pressed spring scales the shutter unless Reduce Motion is enabled. It retains its centered slot when zoom families change.

### Inline zoom anchors

Three always-exposed anchors represent the 1×, 2× and 3× families. The active circle displays actual applied zoom; inactive labels display their bases. An exact base toggles to its half-step; other values return to base. The active family recenters with a smooth transition unless Reduce Motion is enabled. Accessibility names the family, reports the value and supplies direct base/half-step actions and adjustment. This implementation does not establish a physical lens or focal-length identity.

### Station action and status

Start/Stop is a capsule paired with compact symbol-plus-text status. Start is unavailable during zoom motion; Stop stays available. Status derives from operational state, and completion can trigger a nonrepeating symbol bounce unless Reduce Motion is enabled. The label and symbol keep state understandable without depending on color alone.

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
- **Don't** replace applied zoom with a requested destination, focal-length label or physical lens claim.
- **Don't** treat sampled colors, fixture scenery or schematic storyboard fills as production palette tokens.
- **Don't** infer physical camera quality or complete accessibility acceptance from simulator presentation.
