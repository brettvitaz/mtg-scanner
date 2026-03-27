# iOS Crop-First Batch Scan — Planning Summary

## Goal
Add a crop-first scan flow to the iPhone companion app:
- detect likely MTG card regions on-device
- preview detected crop regions in the iOS UI
- create first-pass crops on-device
- send those crops to a new batch backend endpoint
- have the backend perform a second-pass crop/tightening step before recognition

## Product intent
Improve crop quality, reduce unnecessary image area sent to the backend, and make the scan pipeline more trustworthy by previewing detected card regions before upload.

## Decisions locked

### Backend/API
- Add a **new batch image endpoint**.
- Keep the existing single-image route unchanged.
- If the iPhone detects no cards locally, it should send the full image to the original route for backend-side processing.

### iPhone behavior
- On-device intelligence is limited to:
  - previewing crop regions
  - first-pass crop extraction
- **No crop editing in v1.**
- Photo library images should use the same detection/crop pipeline as camera images.
- In camera mode, crop-region preview should be displayed **live before capture** so the user can judge whether the shot is likely to succeed.
- The user remains fully in control of capture; there is **no auto-capture** in v1.
- A scan-style preview animation is desired (for example: translucent blue crop region with animated scan line).
- Backend crop/detection learnings should be reused as heuristics on iPhone where practical, especially:
  - MTG-like aspect ratio filtering
  - overlap suppression / de-duplication
  - mild crop padding
  - perspective-aware crop thinking
  but the iPhone implementation should use native iOS/Vision tooling rather than attempting a direct OpenCV port.
- Because MTG cards have rounded corners, on-device detection should not overfit to perfect geometric corners; detecting stable straight edges / card-like boundaries may be more reliable than assuming sharp-corner rectangles.

### Camera UX requirements
- Preserve normal camera controls such as zoom and flash.
- Review the camera modal for usability.
- Fix the partially cut-off flash button / top-right control layout issue as part of this work if it is in the touched surface area.

### Batch artifact layout
Use a clear batch artifact layout that distinguishes:
- uploaded first-pass crops
- backend-refined crops
- response + metadata linking them

Recommended shape:

```text
services/.artifacts/recognitions-batch/<timestamp>-<id>/
├── inputs/
│   ├── crop-0.jpg
│   ├── crop-1.jpg
│   └── ...
├── refined/
│   ├── crop-0-tight.jpg
│   ├── crop-1-tight.jpg
│   └── ...
├── response.json
└── metadata.json
```

## Ordering / result mapping
Strict result ordering is not a product requirement.
However, the implementation should still prefer stable ordering where practical.
Longer term, result-to-crop association will matter more once result details can show crop thumbnails.

## Follow-up features already anticipated
- A later results-improvements feature should make a thumbnail of the cropped image available in result details.
- A later crop-enhancement feature should improve detection of two cards that are touching. This is known future work and not expected to be fully solved in v1 of the crop-first pipeline.

## Recommended behavior flow

### Camera flow
1. User opens camera view.
2. App runs live on-device card-region detection on preview frames.
3. App shows live crop-region preview with scan animation while the user frames the shot.
4. User decides when to capture.
5. After capture, app uses the most recent valid detected regions to create first-pass crops.
6. If card regions are found:
   - create first-pass crops on-device
   - upload crops to new batch endpoint
7. If no card regions are found:
   - upload original image to existing single-image endpoint

### Photo library flow
1. User selects image from Photos.
2. App runs the same on-device detection.
3. App shows crop preview.
4. If card regions are found, upload first-pass crops to batch endpoint.
5. Otherwise, fallback to the existing single-image endpoint.

## UX note on live preview
Live crop preview during camera framing is a requirement.
The user should see whether the app believes the shot is likely to succeed **before capture**, but the user remains in control of when to press capture.
This means the preview should guide capture, not force timing pressure or automatic submission.
The live overlay should be reasonably stable and not flicker aggressively.

## Feasibility
This feature is feasible in the current project and is a medium-complexity extension of the existing architecture.

### Why it fits
- iOS app already captures and uploads images.
- Backend already performs detection/cropping/recognition work.
- Crop quality is already known to be an important driver of recognition quality.
- Multi-card semantics and artifact logging already exist.

## Key technical risks
- On-device rectangle detection quality on real MTG photos
- Coordinate mapping / crop extraction correctness on iOS
- Keeping the camera UI usable while adding crop preview behavior
- Clean backend contract for multi-image uploads and batch artifact output

## Deterministic testing guidance
To maximize agent success, iOS work should not rely only on subjective manual inspection.

### Desired test strategy
1. **Build must pass**
   - `xcodebuild -project apps/ios/MTGScanner.xcodeproj -scheme MTGScanner -sdk iphonesimulator -configuration Debug build`
2. Add testable state/logic for:
   - live preview state while camera is active
   - fallback to original route when no cards are detected
   - batch upload path when crops are detected
3. If practical, add simulator UI testing for the live preview/fallback/upload path.
4. Capture screenshots for camera modal review and crop preview states.
5. Manual review should explicitly verify:
   - flash button fully visible
   - zoom/flash still usable
   - crop preview understandable
   - user remains in control of capture

## Suggested implementation phases

### Phase 1
- New batch crop endpoint in backend
- iOS on-device crop detection + preview
- first-pass crop upload
- backend second-pass crop tightening + recognition
- fallback to old route when no crops detected

### Phase 2
- improve preview polish
- improve crop/result association in the UI
- add crop thumbnails in result details

## Scope notes for implementation handoff
- Keep the existing single-image route intact.
- Prefer a separate batch endpoint instead of overloading the current endpoint.
- Preserve current response contract unless explicitly changed for the new batch route.
- Keep v1 preview-only; no crop editing UI.
