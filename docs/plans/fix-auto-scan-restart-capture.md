# Auto Scan restart and manual capture

## Behavior

Start creates a fresh motion-detection session and waits for a card arrival. Stop clears
pending capture, motion/reference history, and calibration. A stationary card after
restart needs movement or manual capture. Previously queued recognition jobs continue.

The shutter works while Auto Scan is running or stopped. It bypasses the settling delay,
shares automatic capture/cropping/recognition, and uploads the original photo when no
crop is found. A capture while stopped never starts scanning or calibrates detection.
Repeated taps cannot overlap capture or crop preparation.

Session identifiers reject old signals, timers, photo completions, and crop completions
after Stop/Start or mode exit. An outstanding photo/crop operation retains its lock
until it finishes; its invalidated results are discarded.

## Verification

- Worktree: `fix-auto-scan-restart-capture`; based on master after fetching origin
  (master one commit ahead, zero behind). Main-worktree pricing edits left untouched.
- Required API bootstrap, Card Kingdom import, and MTGJSON update completed.
- Baseline simulator app build passed; baseline API tests: 243 passed.
- Baseline `make lint` failed in NumPy dependency stubs: mypy targets Python 3.11 but
  the installed NumPy 2.5.3 stubs use Python 3.12 type-statement syntax.
- Baseline `make ios-lint`: eight errors. Two errors in the touched Auto Scan tests
  were corrected with a throwing `XCTUnwrap` helper and clearer payload preparation.
- Full iOS 18.6 suite: 425 passed. Two subsequently added acceptance tests passed in
  a focused run (10 capture lifecycle tests passed). Final full iOS 26.4.1 suite:
  428 passed, including the stopped-mode crop/calibration regression. The initial
  OS=26.4 destination was unavailable; rerun used Xcode's installed OS=26.4.1.
- Final simulator app build passed; final API regression suite: 243 passed.
- Strict SwiftLint on all six changed Swift files: zero violations. Global
  `make ios-lint` still reports the same six unrelated baseline errors.
- Inspected the final API test artifact's metadata and response: mock recognition
  and MTGJSON validation details remain available.
- Frame regressions exercise actual BGRA sample buffers through the presence queue,
  motion detection, zone filtering, and signal delivery. Calibrated and uncalibrated
  sessions both detect another card after reset without acknowledging the first capture.
- Lifecycle tests cover stopped/watching/settling manual capture, rapid taps, failure
  retry, stale signals, Stop/Start during photo/crop, automatic capture after restart,
  cropping/calibration, and preservation of original upload bytes on crop fallback.
- Temporary simulator-hosted screenshot diagnostics exported blank images; removed
  the diagnostic test. Visual appearance is unverified. No physical-camera test was run.

## Code review

Every changed Swift file, the new lifecycle tests, and README were reviewed.

| Criterion | Result | Evidence |
| --- | --- | --- |
| Correctness | Pass | Full reset, session checks at asynchronous boundaries, and capture lock are covered by regressions. |
| Complexity / simplicity | Pass | Short helpers, flat guards, no new protocol hierarchy; injection closures exercise actual orchestration. |
| No scope creep | Pass | Only Auto Scan controls/lifecycle, related tests, and documentation changed. |
| Meaningful tests | Pass | Real frame processing and suspended photo/crop paths; removing reset or session checks breaks regressions. |
| Best practices / safety | Pass | No new force unwraps or suppressions; weak callback captures; UI on main actor, tracker state on its serial queue. |
| API contract | Pass | Recognition schemas, providers, and endpoints unchanged. |
| Artifacts / observability | Pass | Existing raw-capture debug saving, recognition artifacts, and failure status preserved. |
| Static analysis | Fail | Six pre-existing SwiftLint errors remain in AddCard and CardDetail; Python baseline typing incompatibility also remains. |

The user explicitly authorized overriding the lint guidance after reviewing these
results. Commit proceeds with the documented existing lint failures; no lint rules
were suppressed or weakened. Unrelated lint repairs were not performed because
AGENTS.md prohibits scope creep. Build and test requirements remain satisfied.
