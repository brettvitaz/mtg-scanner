---
paths:
  - "services/api/app/services/card_detector.py"
  - "services/api/app/services/card_validation.py"
  - "services/api/app/services/recognizer.py"
  - "services/api/app/services/openai_compat.py"
  - "services/api/app/services/mtgjson_index.py"
  - "apps/ios/MTGScanner/Features/CardDetection/**/*.swift"
  - "apps/ios/MTGScanner/Features/Scan/**/*.swift"
---

# Detection, Recognition, and Cropping Rules

## Verification requirements
- Test against real sample images in `samples/test/` when possible.
- Inspect artifacts under `services/.artifacts/recognitions/` after changes.
- Check **crop quality**, not just card count.
- Run `make api-test` to confirm detection regression tests still pass.
- Verify both mock and real provider paths if touching provider logic.

## Backend detection (OpenCV)
- `card_detector.py` uses contour-based detection with aspect ratio filtering.
- Binder page detection requires 9 cards on `binder_page_1.jpg` — this is a regression test.
- Existing two-card regression on real samples must also pass.
- Overlap suppression must dedupe true duplicates while preserving adjacent binder cards.

## iOS detection
- **Table mode**: YOLOv8n Core ML model via `VNCoreMLRequest`. Do not switch to Vision rectangles for table mode.
- **Binder mode**: `VNDetectRectanglesRequest` for page detection → `GridInterpolator` for 3×3 grid.
- `CardTracker` provides EMA smoothing + presence hysteresis — do not remove stabilization.
- Session preset must be `.hd1920x1080`. Do not use `.photo` or `.hd4K`.

## Coordinate transforms (iOS) — critical
- Pass native landscape `CVPixelBuffer` to `VNImageRequestHandler` with **no orientation hint**.
- Use `previewLayer.layerPointConverted(fromCaptureDevicePoint:)` for Vision → screen mapping.
- Apply Y-flip before `layerPointConverted` (Vision origin is bottom-left).
- Do NOT attempt manual coordinate math — the built-in conversion handles aspect fill and device rotation.

## Cropping (iOS)
- `CardCropService` normalizes UIImage orientation upfront before any processing.
- Uses `CIPerspectiveCorrection` for perspective-corrected crops.
- Renders at natural output extent — do not force a specific aspect ratio.

## MTGJSON validation
- Validation is post-recognition, pre-response. It does not replace the recognizer.
- Matching cascade: exact triple → title+set → title+number → set-name resolution → normalized → fuzzy → no-match.
- Confidence adjustments: exact keeps/boosts, fuzzy reduces, no-match reduces meaningfully.
- Graceful degradation: if SQLite DB is missing, skip validation and return raw results.

## Provider strategy
- Mock is default for tests — no network or API keys needed.
- OpenAI for real evaluation. OpenAI-compatible for local models.
- Do not add new provider types unless the OpenAI-compatible path proves insufficient.
- Response modes: `json_schema` (OpenAI), `json_mode` (Ollama), `raw` (LM Studio).
