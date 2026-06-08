# Findings: Research Review of iOS Card Crop Implementation

**Date:** 2026-06-07
**Purpose:** Evaluate the implemented crop quality improvement against industry research and call out gaps that require work to make the feature complete.

## Executive Summary

The core architecture is correct: `VNDetectRectanglesRequest` + YOLO hints is the right approach for MTG cards. ROI expansion, dual-pass detection, multi-factor ranking, and fallback strategy all align with production best practices.

Three areas require additional work before the feature is production-ready:

1. **Blur detection is absent** — all production scanning apps include it
2. **Crop quality scoring uses strict AND logic** — a weighted approach would be more forgiving and useful
3. **`CIContext` thread safety** — `@unchecked Sendable` with shared context is a latent concurrency bug

Additionally, edge classification and skew detection thresholds need calibration for different card types (foil, colored borders, black borders).

---

## Research Findings by Topic

### 1. Core Detection Approach

**Decision:** Use `VNDetectRectanglesRequest` + YOLO hints (implemented)

**Research verdict: Correct.**

- `VNDetectDocumentSegmentationRequest` (VisionKit's underlying model) is trained exclusively on *documents with text* — paper sheets, receipts, labels. MTG cards are visually distinct: art-heavy, small (2.5"×3.5"), colored borders, foil effects. The document segmentation model would likely fail on face-down cards and non-standard card types.
- `VNDocumentCameraViewController` is not customizable (full-screen modal, no API changes) and document-focused. Not viable for card scanning.
- No production app was found that used VisionKit or DocumentSegmentation for non-document rectangular objects.
- The YOLO + Vision hybrid pattern is standard in production (BoardSnap, CheckCaptureKit, open-source implementations).

### 2. ROI Expansion

**Current value:** 18% (`CardCropService.hintROIPadding`)

**Research verdict: Correct.**

Industry standard is 15–25% expansion. The 18% value is well within the optimal range:
- < 15%: Vision misses card edges due to perspective distortion
- > 30%: False positives from background rectangles, increased compute

### 3. Dual-Pass Vision Detection

**Current approach:** ROI pass + full-image pass, combined results

**Research verdict: Acceptable trade-off.**

Production consensus is that dual-pass is preferred for quality-critical captures. The 1.5–2× processing time (~45–60ms vs ~30ms) is accepted as a trade-off for accuracy. Since this runs on still photos (not live frames), latency impact is minimal.

**Unverified:** The plan's risk note ("capture-to-enqueue timing should be checked on device") was never measured.

### 4. Candidate Ranking

**Current approach:** Multi-factor scoring (confidence 0.65 + aspect closeness 0.35 + area + hint overlap)

**Research verdict: Correct.**

Confidence-only ranking is insufficient. Multi-factor scoring with geometric and semantic signals is the production standard.

### 5. Crop Quality Evaluation

**Current approach:** Edge brightness analysis + skew detection via edge point binning, strict AND pass/fail

**Research verdict: Reasonable architecture with significant gaps.**

| Aspect | Current | Production Standard | Gap |
|--------|---------|---------------------|-----|
| Edge metrics | Edge strip pixel classification with saturation filter | Gradient-filtered edge analysis + per-edge reporting | Medium — no gradient filtering; saturation threshold (0.28) misclassifies gold/colored borders |
| Skew detection | Edge point binning, ±0.5° range, default 0.20° threshold | PCA or Hough-based, 0.5°–2.0° acceptable range | Medium — 0.20° is stricter than literature; edge threshold (0.18) too low, picks up card text/artwork |
| Blur detection | **Not implemented** | Laplacian variance (standard, O(n), fast) | **High** — #1 quality signal in production apps |
| Scoring logic | Strict AND (all checks must pass) | Weighted scoring with graceful degradation | Medium — a slightly-skewed but otherwise good crop gets rejected outright |
| Thresholds | Hardcoded magic numbers | Calibrated per card type / adaptive | Medium — foil cards, black borders, colored backgrounds may break thresholds |

### 6. Coordinate Conversion

**Current approach:** `y: 1.0 - box.maxY` for YOLO→Vision conversion

**Research verdict: Correct.**

Matches the production pattern of flipping the Y-axis for Vision's bottom-left origin.

### 7. Fallback Strategy

**Current approach:** Axis-aligned crop from YOLO box when Vision finds nothing

**Research verdict: Correct.**

Standard fallback hierarchy: axis-aligned crop → document segmentation → manual adjustment. Two-step approach is appropriate for this scope.

### 8. Split-Card Handling

**Current approach:** Merge adjacent rectangles when geometry indicates a single card (`CardCropService+Quality.swift`)

**Research verdict: Appropriate.**

Matches production patterns for handling nested/adjacent detections. The geometry-based merge logic (overlap ratio, vertical gap, center distance) is well-designed.

---

## Required Work to Complete the Feature

### P0: Blur Detection (High Gap)

**Why it matters:** Blur is the #1 quality signal in production scanning apps (Genius Scan, Adobe Scan, Dynamscan, Microsoft Lens). A sharp but slightly skewed crop is better than a blurry perfect crop. Without blur detection, the system cannot distinguish between a valid card photo and one that's too blurry for recognition.

**What to implement:**

Add Laplacian variance blur detection to `CropQualityEvaluator`:

```swift
// In CropQualityEvaluator.evaluate():
let blurScore = Self.computeLaplacianVariance(image)  // Returns 0.0–1.0
let isBlurry = blurScore < blurThreshold

// In CropQualityResult:
let passes: Bool  // Now includes blur check
let isBlurry: Bool  // New field

// In weighted scoring:
let totalScore = edgeScore * 0.35 + skewScore * 0.25 + blurScore * 0.25 + contentScore * 0.15
```

**Implementation details:**
- Apply a 3×3 Laplacian kernel to a sampled center region (240×336, same as skew detection)
- Compute variance of the result
- Threshold: variance < 200 = blurry, 200–500 = acceptable, > 500 = sharp
- O(n) single-pass on sampled region — negligible performance impact

**Files to modify:** `CropQualityEvaluator.swift`, tests

---

### P0: CIContext Thread Safety (Latent Bug)

**Why it matters:** `CIContext` is not thread-safe. The current implementation declares `CardCropService: @unchecked Sendable` with a shared `ciContext` property. If `detectAndCrop` is called concurrently from multiple tasks, this could produce undefined behavior or crashes.

**What to implement:**

Either:
1. **Make `ciContext` local per invocation** (simplest, zero concurrency risk):
```swift
func detectAndCrop(image: UIImage, hint: CardCropHint? = nil) async -> CardCropResult {
    let ciContext = CIContext()  // Local, not shared
    // ... use ciContext in cropCard()
}
```

2. **Or serialize CI operations** on a serial dispatch queue if context reuse for performance is needed.

**Files to modify:** `CardCropService.swift`

---

### P1: Weighted Crop Quality Scoring (Medium Gap)

**Why it matters:** Strict AND logic means a crop that passes 2 of 3 quality checks gets rejected entirely. Production apps use weighted scoring for graceful degradation and to rank multiple valid crops.

**What to implement:**

Replace boolean pass/fail with a weighted score:

```swift
struct CropQualityResult {
    let passes: Bool
    let isUnderCrop: Bool
    let isOverCrop: Bool
    let isSkewed: Bool
    let isBlurry: Bool  // New, after P0 blur detection
    let score: CGFloat  // 0.0–1.0 weighted composite
    let edgeMetrics: EdgeMetrics?
    let layoutMetrics: PrintedLayoutMetrics?
}

// In CardCropService.firstAcceptableSingleCrop():
// Use score for ranking: try highest-scoring crop first
// Accept crops with score > acceptanceThreshold (e.g., 0.6)
// Reject only when no crop meets threshold
```

**Scoring weights (recommended):**
- Edge quality: 0.35
- Skew: 0.25
- Blur: 0.25
- Content presence: 0.15 (future)

**Files to modify:** `CropQualityEvaluator.swift`, `CardCropService.swift`, tests

---

### P2: Edge Classification Calibration (Medium Gap)

**Why it matters:** Current edge classification has two issues that may cause false positives/negatives on specific card types:

1. **Saturation threshold (0.28) is too aggressive** for MTG cards — gold borders, colored card frames, and even white borders with subtle shading fall below this threshold, causing misclassification as "card content" rather than "light background."

2. **No gradient filtering** — the edge strip counts all pixels, not just pixels at actual edges. A white spot in the background counts the same as a card border.

**What to implement:**

1. Lower saturation threshold to ~0.15–0.20 for gold/colored border detection
2. Add gradient magnitude filtering to the edge strip — only count pixels with high gradient as edge pixels
3. Consider per-edge analysis (top/left/right/bottom separately) for more precise diagnostics

**Files to modify:** `CropQualityEvaluator.swift` (EdgeMetrics), tests with foil/black-border card fixtures

---

### P2: Skew Detection Threshold Calibration (Medium Gap)

**Why it matters:** Two issues in the current skew detection:

1. **Edge magnitude threshold (0.18) is too low** — picks up card text, artwork details, and border texture as "edges," making angle measurement noisy.
2. **0.20° default threshold is stricter than literature** — document processing papers typically use 0.5°–2.0° as acceptable skew.
3. **Directional filter (|gy| > |gx| × 1.30) only detects near-vertical edges** — if the card is rotated, its "vertical" edges become more horizontal and detection fails.

**What to implement:**

1. Raise edge magnitude threshold to ~0.30–0.40 to focus on strong edges (card borders)
2. Include both horizontal and vertical edge points (remove or relax the directional filter)
3. Consider sampling closer to crop boundaries where card borders are most prominent
4. Default threshold: 0.5° (more permissive, still tight for card scanning)

**Files to modify:** `CropQualityEvaluator.swift` (PrintedLayoutMetrics), tests

---

### P2: Device Latency Measurement (Unverified Assumption)

**Why it matters:** The plan noted "capture-to-enqueue timing should be checked on device." Dual-pass Vision detection adds ~1.5–2× processing time vs single-pass. On older devices or in battery-throttled conditions, this could be noticeable to users.

**What to implement:**

Add timing instrumentation (debug-only):
- Log `detectAndCrop` duration per call
- Compare ROI pass vs full-image pass timing
- Measure on iPhone 13, iPhone 15, and iPad to cover the device range
- Set an upper bound (e.g., 100ms) and warn if exceeded

**Files to modify:** `CardCropService.swift` (debug logging), test harness

---

## Research: What Production Apps Do That We Don't

| Feature | Genius Scan | Adobe Scan | VisionKit | Our Implementation |
|---------|-------------|------------|-----------|-------------------|
| Manual crop adjustment | Yes (drag corners) | Yes | Yes | No |
| Blur detection | Yes | Yes | N/A (built-in) | **No** |
| Weighted quality scoring | Yes | Yes | N/A | No (strict AND) |
| Per-edge diagnostics | Yes | No | No | No |
| Adaptive thresholds | Yes | Yes | N/A | No (hardcoded) |
| Auto-rescan prompt | Yes | Yes | N/A | No |

Manual crop adjustment is explicitly out of scope for this work effort. The other gaps (blur, weighted scoring, adaptive thresholds) are addressable within the current architecture.

---

## Implementation Priority Summary

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| **P0** | Blur detection (Laplacian variance) | ~1 day | High — missing #1 quality signal |
| **P0** | CIContext thread safety | ~2 hours | High — latent concurrency bug |
| **P1** | Weighted crop quality scoring | ~2 days | Medium — graceful degradation |
| **P2** | Edge classification calibration | ~1 day | Medium — specific card types |
| **P2** | Skew detection calibration | ~1 day | Medium — false rejections |
| **P2** | Device latency measurement | ~2 hours | Low — verify assumption |

**Total effort to complete:** ~5–6 days of focused work.
