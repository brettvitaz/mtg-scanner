# Findings: Completion Review of iOS Card Crop Implementation

**Date:** 2026-06-07
**Reviewer:** Synthesis of code review (`CardCropService`, `CardCropService+Quality`,
`CropQualityEvaluator`, `RectangleFilter`, `AutoScanViewModel`, `AppModel`, `ScanView`),
the existing work-effort docs (`review.md`, `findings.md`, `future-work.md`), and a
cross-check against `findings2.md`.
**Purpose:** State what is actually done, correct one inaccurate claim in `findings2.md`,
and define the concrete work required before this feature can be called complete.

---

## Executive Summary

The implementation **faithfully executes the plan** and meets every explicitly stated
requirement in `request.md`. The architecture (Vision rectangle refinement + YOLO hint,
perspective correction, shared crop service across all three capture flows, YOLO
axis-aligned fallback, debug-only raw-capture saver) is the correct Apple-native approach
given the no-new-ML constraint. The targeted crop regression suite passes.

It is **not yet a complete feature** for two reasons that the prior docs underweight:

1. **The success metric was never measured.** The goal is *better recognition*. Success
   is currently verified only by crop-geometry heuristics, with no before/after
   recognition-accuracy comparison. We do not actually know recognition improved.
2. **The quality oracle is overfit and admits known false negatives.** `CropQualityEvaluator`
   uses hyper-specific hardcoded threshold bands tuned to named fixtures. The team's own
   `findings.md` documents that `IMG_1968-crop3` and `IMG_1979-crop2` pass falsely. The
   intended replacement — annotated ground-truth quads — was deferred and the raw-capture
   saver that would bootstrap real fixtures has never run on a device.

Everything below is organized as: (A) what is verified done, (B) a correction to
`findings2.md`, (C) required follow-up work to reach "complete," prioritized.

---

## A. What Is Verified Done

| Requirement (`request.md`) | Status | Evidence |
|----------------------------|--------|----------|
| ≤5% background bleed per edge | Done | `CardCropService.cropPadding = 0.025` |
| Perspective correction for angled cards | Done (with caveat C4) | `CIPerspectiveCorrection` in `cropCard` |
| Consistent crop across manual / photo-library / auto-scan | Done | All three route through `CardCropService.detectAndCrop` |
| No live-frame latency added | Done | Refinement runs post-capture only |
| Crop-disabled = full-image upload | Done | Unchanged full-image path preserved |
| No recognition / API / server / model changes | Done | No contract or schema changes |
| Apple-native frameworks only | Done | Vision, CoreImage, UIKit, AVFoundation |
| Debug-only raw-capture saving, default-off | Done | `#if DEBUG` guarded; Release build guard passed |

Flow unification (a core plan goal) is genuine:

- **Manual crop-enabled:** `ScanView → enqueueCapturedImage(cropEnabled:)` → `cropImage(image, nil)` (multi-crop).
- **Photo-library crop-enabled:** `AppModel` → `cropService.detectAndCrop(image:)` (multi-crop).
- **Auto-scan:** `cropCapturedPayload` → `CardCropHint(yoloBoxTopLeft:, preferSingleCrop: true)` (hinted single-crop with validation).

Test status: the focused crop/view-model regression suite passes on the
`iPhone 16` simulator, iOS 18.6, via the `MTGScannerKitTests` scheme (re-confirmed
`** TEST SUCCEEDED **` during this review).

---

## B. Correction to `findings2.md`

`findings2.md` lists "CIContext thread safety" as a **P0 latent concurrency bug**. This is
incorrect and should not be actioned.

- `CIContext` is documented by Apple as **thread-safe** and is explicitly designed to be
  created once and shared across threads. The Core Image type that is *not* thread-safe is
  `CIFilter`.
- The code already creates a fresh `CIFilter` locally inside every `cropCard` invocation
  (`CIFilter(name: "CIPerspectiveCorrection")`), so there is no shared mutable filter state.
- `CardCropService`'s only stored properties are the immutable/thread-safe `ciContext` and a
  `RectangleFilter` value type, which is what justifies `@unchecked Sendable`.
- In practice the two call sites use **separate** `CardCropService` instances
  (`AppModel.cropService` vs. the injected closure in `AutoScanViewModel`).

There is no bug to fix here. The remaining `findings2.md` recommendations (blur detection,
weighted scoring, threshold calibration, latency measurement) are valid and are folded into
section C below with corrected priorities.

---

## C. Required Follow-Up Work to Reach "Complete"

### C1 (P0) — Validate against recognition outcomes

**This is the single most important gap.** The feature's purpose is improved recognition,
yet success has only been measured on crop geometry.

- Run a recognition A/B on a fixed image set: crop-off (full image) vs. crop-on (current
  pipeline), comparing identification accuracy and confidence.
- Use the existing eval harness (`evals/run_eval.py`) where possible so results are
  repeatable and comparable to other recognition work.
- Record baseline numbers in this work effort so future crop changes can be regression-checked
  against recognition, not just geometry.

**Done when:** there is documented evidence that crop-on recognition is at least as good as,
and ideally better than, crop-off on the eval set — and a repeatable command to re-measure.

### C2 (P0) — Build annotated ground-truth fixtures

The current oracle is heuristic and self-admittedly leaks false negatives. Replace it as the
primary regression guard.

- Run the debug raw-capture saver **on a physical device** (it has only ever been spy-tested;
  its `PHPhotoLibrary` add-only path is unverified on hardware).
- Capture manual and auto-scan examples covering: under-crop, over-crop, skewed bin/stack,
  foil, black-border, colored-border, split card, partial card, and known-good.
- Store source images under a test fixture directory with a manifest of expected card quads
  (normalized coordinates), expected failure class, capture mode, and scene notes.
- Make annotated-quad assertions the primary crop regression test; keep the labeled-output
  evaluator only as a diagnostic classifier.

**Done when:** crop regression tests assert against annotated geometry, and the known false
negatives (`IMG_1968-crop3`, `IMG_1979-crop2`) are correctly classified.

### C3 (P1) — Blur / sharpness gating

Valid addition (raised in `findings2.md`). Note this is a **scope extension** — the original
request covered tightness/de-skew/orientation, not capture sharpness — so confirm it is wanted
before building.

- Add Laplacian-variance blur detection to `CropQualityEvaluator` on the same sampled center
  region used for skew. O(n), negligible cost.
- The auto-scan path already has upstream `MotionBurstDetector` settling, which mitigates
  *motion* blur but not *focus* blur; the highest marginal value is on the **manual** capture
  path.
- Calibrate the threshold against the C2 fixtures, not against a guessed constant.

**Done when:** blurry captures are flagged/rejected, with the threshold derived from real
fixtures and verified not to reject sharp foil/holo cards.

### C4 (P1) — Perspective-correct the hard-case fallback

Requirement 2 (de-skew) is silently violated on the worst inputs. When Vision refinement
fails on an *angled* card, the fallback is `axisAlignedCrop` — not perspective-corrected and
including skew/background. This is the exact failure mode that motivated the work.

- Investigate using the YOLO hint to drive a perspective correction (or a second
  constrained Vision pass) instead of a raw axis-aligned crop.
- At minimum, document this as a known limitation in user-facing terms if it remains
  unaddressed.

**Done when:** angled cards that fall through to fallback are de-skewed, or the limitation is
explicitly accepted with fixture evidence of its frequency.

### C5 (P2) — Replace strict AND with calibrated weighted scoring

`CropQualityEvaluator` currently rejects a crop if any single check fails. A weighted composite
allows graceful degradation and lets the service rank multiple valid crops.

- Move to a 0.0–1.0 composite score with an acceptance threshold; try highest-scoring crop
  first in `firstAcceptableSingleCrop`.
- **Critical:** calibrate the weights against the C2 fixtures and the C1 recognition A/B.
  Weighted scoring with guessed weights just trades magic thresholds for magic weights.

**Done when:** scoring weights are calibrated against real fixtures and do not regress the C1
recognition baseline.

### C6 (P2) — Threshold calibration for card variety

The hardcoded bands are tuned to a narrow fixture set and will misbehave on common MTG cards.

- Edge classification: the `saturation < 0.28` test in `MutableEdgeCounters` misclassifies
  gold/colored borders; add gradient filtering so only true edge pixels are counted.
- Skew detection: the `> 0.18` magnitude threshold picks up artwork/text; the
  `|gy| > |gx| * 1.30` near-vertical-only filter misses rotated cards; the ±0.5°/0.20° band is
  stricter than literature (0.5°–2.0°).
- Re-derive all of these from the C2 fixtures rather than ad hoc tuning.

**Done when:** foil, black-border, and colored-border fixtures classify correctly without
regressing existing fixtures.

### C7 (P2) — Device latency measurement

The plan flagged "capture-to-enqueue timing should be checked on device"; it never was.
Dual-pass Vision adds ~1.5–2× detection time.

- Add debug-only timing instrumentation to `detectAndCrop`.
- Measure capture-to-enqueue across a device range (older + current) and set an upper bound.

**Done when:** measured latency is documented and within an acceptable bound on target devices.

---

## Priority Summary

| Priority | Item | Why | Blocks "complete"? |
|----------|------|-----|--------------------|
| **P0** | C1 Recognition-outcome A/B | Feature's actual purpose is unmeasured | Yes |
| **P0** | C2 Annotated ground-truth fixtures | Current oracle is overfit with known false negatives | Yes |
| **P1** | C3 Blur gating (scope extension) | #1 production quality signal; confirm desired | Conditional |
| **P1** | C4 Perspective-correct fallback | De-skew requirement violated on hard cases | Yes |
| **P2** | C5 Weighted quality scoring | Graceful degradation; needs C2 to calibrate | No |
| **P2** | C6 Threshold calibration | Card-type robustness; needs C2 to calibrate | No |
| **P2** | C7 Device latency measurement | Verify an unverified assumption | No |

**Do NOT action:** `findings2.md` "CIContext thread safety (P0)" — not a real bug (see B).

---

## Recommendation

The delivered work is solid, correctly scoped, and shippable as a first pass behind the
existing crop toggle. To call the feature **complete**, the gating work is C1 + C2 + C4:
prove recognition actually improves, replace the overfit heuristic oracle with annotated
fixtures, and make sure the hard-case fallback honors the de-skew requirement. C3 and C5–C7
should be sequenced *after* C2 exists, because every threshold/weight decision depends on real
fixtures to calibrate against — tuning them now would only deepen the overfit.
