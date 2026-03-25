# Agent Workflow & Findings

## ACP Agent Completion Events

### Problem
Claude ACP sessions do not automatically send completion events to the parent session. This makes it difficult to know when a task is finished without manual checking.

### Solution
Add an explicit wake trigger instruction to agent tasks:

```
When completely finished, run this command to notify the parent session:
openclaw system event --text "Done: [brief summary of what was built]" --mode now
```

### Monitoring Fallbacks
If the wake trigger fails or isn't implemented:
1. **Git log polling** — check for new commits (`git log -1`)
2. **Process monitoring** — check for running acpx/claude processes
3. **File system monitoring** — watch for changes in the workspace

### Example Task Template
```
Your task: [description]

When completely finished:
1. Run: openclaw system event --text "Done: [summary]" --mode now
2. Report: files changed, test results, commit hash
```

---

## OpenCV Card Detector Findings

### Initial Issues
- RETR_EXTERNAL only returned outermost contours, missing cards inside scenes
- No upper bound on contour area allowed background to poison results
- Contour area unreliable when only partial edges detected

### Fixes Applied

#### Commit 1: bff6f2a
- Changed RETR_EXTERNAL → RETR_LIST (captures all contours)
- Added MAX_CARD_AREA_PERCENT=0.70 (filters background)

#### Commit 2: 7f58ad1
- Apply convexHull before approxPolyDP (normalizes fragmented contours)
- Use bounding rect area instead of contour area
- Raised MIN_CARD_AREA_PERCENT: 2% → 6%
- Simplified confidence calculation

### Final Results
| Image | Cards Detected | Expected | Status |
|-------|----------------|----------|--------|
| IMG_1611.png | 2 | 2 | ✅ |
| IMG_1612.png | 3 | 3 | ✅ |

### Key Insight
Cards on dark backgrounds (like Eternal Witness) were particularly challenging because partial edge detection created fragmented contours. convexHull normalizes these into proper rectangles.

---

## Project Workflow Requirements

1. **Commit after each feature or change** — documented in `docs/development-workflow.md`
2. **Use wake triggers for ACP agents** — ensure completion events are sent
3. **Test with real images** — verify detection/recognition on actual card photos
4. **Document findings** — keep notes on decisions and debugging in this file

---

## Next Steps (as of 2026-03-25)

- [x] Provider-backed recognition (OpenAI + Mock)
- [x] Multi-card detection (OpenCV + OpenAI fallback)
- [x] OpenCV detector tuning
- [ ] iOS app improvements (camera UX, results display, correction UI)
- [ ] Crops directory fix (artifact store should save individual card crops)
- [ ] Evaluation harness (automated accuracy testing)
- [ ] Ollama/LM Studio support (fallback response modes)
