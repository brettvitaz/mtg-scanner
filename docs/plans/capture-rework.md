# Capture rework — approved contract and completion record

Canonical record for `capture-consistency`, retained on 2026-10-19 for
[PR #139](https://github.com/brettvitaz/mtg-scanner/pull/139). This consolidates the
previous ignored brief and its C/L amendments. It is retrospective documentation,
not a claim that this tracked record existed during implementation. Old local briefs
now forward here; private recordings and raw session logs remain local.

## Approval and authority

- Original proposal v1 approved on 2026-10-18: the user replied “yes” to “Do you approve proposal v1, including these additions, for the replacement brief?” It covered requirements R1–R13, selected direction, native checkpoint, tests and additions; approval alone did not prove implementation or optics.
- Later explicit corrections C1–C11 and L1/L2/L4 were authorized fixes. L3 requested a **proposal only**. The tables below reconcile them; superseded values are history, not effective instructions.
- Recognition correction: “Make 3 notices and a brief subtle shimmer. Everything else is approved.” This supersedes two notices/no shimmer and the earlier single-toast requirement.
- Tabs: “Use the design skill to identify and recommend the correct color for all of the tabs. They must all be the same color.” Native system blue was selected for all five, superseding yellow capture tabs; selected magnification remains yellow.
- Trigger design approved: learn normal variation before Ready, integrate arrival/settlement/rearming, preserve identical-copy scanning, require replay and physical Start/tap/drop tests. User constraint: it “must not significantly increase the overall scanning time.” Verification limits below remain part of the contract.
- Retention authorized on 2026-10-19: “correct the retention gap.” This changes documentation/workflow, not approved product behavior.
- Product implementation: `a6bf5ca5941804d7fe7ee499fa133450ad0bdb35`; first maintenance correction: `be2256e7db1c863125653eaf383e45ac90b4aa8d`. PR remains subject to user review; no merge or cleanup authorized.

The source proposal/storyboard and rejection/reference screenshots remain optional
local design history, not required to recover effective decisions. The proposal v1
hash was `0ea7525e6d05c6bd3bee44f9c191ff5f49bc176169252d904a5fd6432b1f7290`.
Current native composition/tokens are in [DESIGN.md](../../DESIGN.md), with the
[design sidecar](../../.impeccable/design.json). [Earlier findings](capture-design-rework.md)
preserve the rejected treatment. This record governs conflicts; later explicit user
instructions must update it before dependent work.

## Original request (verbatim, historical destination retained)

```text
$feature-design

All work is in the 'capture-consistency' worktree.

Rework the complete Table and Station capture presentation.

Read:
docs/plans/capture-design-rework.md
tmp/feature-briefs/capture-consistency.md

Inspect the current native implementation and the rejection screenshot identified
in capture-design-rework.md.

The implemented visual treatment is rejected. Menu width is only one symptom:
reconsider composition, hierarchy, proportion, spacing, materials, and interaction
as a coherent native camera experience. Preserve useful functional implementation;
do not assume its current visual structure should survive.

The rework document records current requirements, including shared camera
selection. The older brief applies only where it has not been superseded.
Do not reopen settled product decisions.

Use Impeccable’s applicable shaping/concept process. Earlier HTML sketches are
exploration history, not visual authority. Show whole-screen alternatives rather
than isolated control variations. Limit exploration to one focused comparison
and one selected direction unless a concrete feasibility issue requires more.

Separate visual design from camera-policy validation. Protect Station close focus,
binder framing, detail, and device fallbacks.

The build must begin with a native feasibility checkpoint covering the complete
screen and the open zoom selector before implementing the full visual rework.
Specify that checkpoint in the brief.

After approval, save the replacement brief as:
tmp/feature-briefs/capture-rework.md

Do not change production code in this design phase.
```

## Effective requirements and behavior

All rows are approved user decisions, inherited constraints or implementation choices
covered by proposal approval and later explicit corrections. IDs retain the original
contract identities. Requirements and tests use this one effective set.

| ID | Effective contract | Supersession / rationale |
|---|---|---|
| R1 | Replace the whole Table/Station presentation: composition, hierarchy, proportion, spacing, materials and interaction. | Overall treatment was rejected; menu width alone was not the problem. |
| R2 | Continuous full-bleed camera image with local control materials; no added opaque framing blackout or enclosing control band. | Camera references establish fluidity/quality, not Camera app framing bars or lens semantics. |
| R3 | Five native destinations: Table, Station, Results, Library, Settings. Centered manual shutter, latest thumbnail left, equal import/Start/Stop slot right, zoom above, torch nearby. Preserve accepted jobs, Results unseen count and queue actions. | L2 replaces navigation zoom resets. All five selected tab icons **and labels** use native blue, including standard/scroll-edge appearance. |
| R4 | Inline 1×/2×/3× anchors. Inactive tap selects base; active exact base/half cycles 1↔1.5, 2↔2.5, 3↔3.5. Arbitrary pinch value tap returns to family base. No increment setting. | Fixed half-step cycle supersedes dropdown/four fixed choices. |
| R5 | Direct continuous pinch; actual unrounded factor selects family [1,2), [2,3), 3+. Recenter at crossings in either direction; rounded labels cap at 1.9/2.9 until raw boundary. Clamp truthfully to device limits. | C2 corrects preannouncing the next family. No optical quantization. |
| R6 | Smooth interruptible preset movement, retarget from actual value; pinch cancels ramp and follows fingers. Present chosen preset directly during a ramp, actual factor during pinch. Reduce Motion suppresses UI flourish. | C5 supersedes intermediate preset readout counting. Actual factor remains authoritative for safety/interruption. |
| R7 | Protect accepted photo/preparation from every zoom path; no-op selection does not pause. Actual zoom suspends detection and stale generations before movement. Active Station remains active, waits existing 750 ms quiet interval, then rebaselines/resumes automatically. Stop/navigation remain available. | L4 supersedes explicit Start after zoom. No phantom capture from movement. |
| R8 | One capability-based physical-camera policy/common 1× baseline for both modes, with close-focus fallback, continuous focus, 1080p processing, highest configured still dimensions and complete crops. | C11 supersedes deferred shared policy; implementation is required, optical quality remains separately unverified. 125–175 mm stand/1.5× observation is not a universal default. |
| R9 | Truthful Preparing/Ready/Settling/Capturing/Stopped/Paused. Ready requires usable learned reference and released accepted operation; independent of recognition completion. Stable status/action positions, one completion cue, readiness announcement priority, separate capture and recognition retries. | Preparing added by approved trigger correction. No silent consumed candidate. |
| R10 | Up to **three** compact newest-first notices, independently expire after three seconds; fourth evicts oldest while Results preserves all. One notice at accessibility sizes. No visible close icon; accessible dismissal. Single subtle **0.8 s** foil shimmer, absent under Reduce Motion. Aggregate “N pending” with latest thumbnail includes queued/active requests; separate failure actions, no pointless close cross. Notifications overlay top without moving capture/status controls; preference suppresses notices, never persistence/queue/errors. | Supersedes single toast, two notices and shimmer removal. Aggregate queue is not per-image job progress. |
| R10 torch | Tap toggles remembered level; hold/accessibility action opens horizontal brightness bar. Top read-only percentage once; presets 1/10/25/50/75/100%; relative 1% drag without touch-down jump. One preset haptic, none for drag/exit. | Preserve approved torch behavior; no new oversized control. |
| R11 | Native feasibility checkpoint covers full screen and actual exposed inline selector/transitions before full styling. | Closed-button width/browser sketch is insufficient. Completed checkpoint remains separate from optical acceptance. |
| R12 | iOS capture/tests/docs scope. Separate behavior, rendering, independent visual judgment and physical acceptance; preserve worktree/artifacts pending explicit cleanup. | No backend/provider/contract/collection redesign. Reframing stays proposal-only. |
| R13 | Fluid native composition with stable geometry, ≥44 pt targets and Dynamic Type/compact adaptation; temporary new-capture/Start lock during actual zoom movement, Stop available. | Initial 56 pt/title3 zoom sizing revised by C3/C4/C9. Use current DESIGN tokens, not historical storyboard pixels. |

### Correction identities and selected native direction

| Amendment | Effective requirement / rationale |
|---|---|
| C1 | Camera/applied/presented zoom synchronized through navigation; first tap works. L2 resolves navigation to per-mode saved actual zoom, not label-only reset. |
| C2 | R5 family-bounded pinch rounding. |
| C3/C4 | Zoom matches torch local material and visible scale, no selected-only black backing; ≥44 pt targets and scalable text. |
| C5 | R6 chosen-preset presentation, not counting intermediate values. |
| C6/C7/C8 | Equal secondary slots; status text cannot shift Start/shutter. Centered independent status above framing, with Table's hidden non-accessible placeholder maintaining geometry. |
| C9 | Deliberate native rhythm: 76 pt shutter/64 pt inner disk; 48 pt secondary controls; cluster max 420 pt, 20 pt side inset and 24 pt control gaps. Current DESIGN supplies adaptive spacing/material/text tokens. Compact/AX torch lift avoids collision. |
| C10 | Diagnose and remove application-caused zoom stutter; source timing/native motion evidence and optical smoothness claims remain separate. |
| C11 | R8 single common physical-camera policy implemented, without asserting optical acceptance. |
| L1 | Single movable AVCaptureVideoPreviewLayer with visible-controller ownership; warm session across capture tabs, stop outside capture/background. |
| L2 | Restore each capture mode's saved actual zoom. Supersedes all earlier 1× navigation-reset instructions. |
| L3 | Preview-only Station reframing/Reset remains a **proposal**, no control, sensor offset, changed photo or crop implemented/authorized. |
| L4 | R7 retain active Station through zoom, clear stale tracking and rebaseline automatically. Supersedes stopped/explicit-Start requirements and historical paused storyboards. |

Selected world is a fluid native viewfinder (Operate mode), white shutter dominant,
compact yellow selected magnification on shutter axis, quiet neighboring labels,
local system materials, native blue selected navigation. Independent status and
thumbnail/queue do not move with completion notices. No enclosing toolbar, focal-length
labels, lens selector or new zoom popup. Current rendered state takes precedence over
schematic reference dimensions; optical validation never follows from visual approval.

Queue recovery retains explicit Cancel pending, Retry failed and Dismiss failures
actions. A thumbnail placeholder preserves pending activity when its image is cleared.
No per-image progress is implied where job identity is unavailable.

## Production-path test map

Test sources are under [MTGScannerKitTests](../../apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/)
and [CaptureControlsTests](../../apps/ios/MTGScannerUITests/CaptureControlsTests.swift).
Visual states/routes are documented in [iOS guidance](../../apps/ios/AGENTS.md).

| Effective IDs | Coverage / regression that must fail |
|---|---|
| R1–R3, R13; C3/C4/C6–C9 | Full native Table/Station, bright/dark, compact/tablet/AX, all status, open zoom/brightness and recognition routes; independent finish review. Restoring opaque band, misaligning slots, moving controls with status/notices or shrinking targets must fail rendering review. All five active tabs checked, not only camera siblings. |
| R4–R6; C1/C2/C5/C10; L2 | ZoomPresetTests, ZoomFactorTests, CaptureZoomWiringTests and CaptureControlsTests cover base/half cycles, raw boundaries/rounding, no-op/clamps, retarget/interruption, mode restore and preset presentation. Removing half-step cycle, using rounded family or stale callbacks must fail. Simulator logic is not optical-motion proof. |
| R7/R9/R13; L4 | StationFeedbackTests, StationTrackerIntegrationTests and hosted/UI wiring cover suspension, accepted locks, stale generations, Stop, post-zoom resume and truthful readiness. Removing gates or requiring a new Start must fail. |
| R8; C11; L1 | AutoScanCameraTests, CameraPreviewLifecycleTests and wiring/native lifecycle tests cover shared capability/fallback policy, dimensions, single preview ownership, warm capture navigation and background stop. Reintroducing mode-specific selection or competing layers must fail. Physical focus/framing is separately owed. |
| R10 | CaptureNotificationTests and native CaptureControlsTests cover three notices, independent expiry/eviction, AX single notice, shimmer/Reduce Motion, preferences, persistence, queue/recovery and torch drag/preset semantics. Restoring single toast, visible close, shared expiry or preference-based data loss must fail. |
| R9 trigger correction | StationTrackerIntegrationTests and StationPhysicalReplayTests cover noisy settlement, identical arrivals, bounded rearming/calibration and **60 stationary learning phases**. Removing low-pass resampling or consuming an unsettled candidate must fail. Optional recording replays skip explicitly when private movies are absent; portable regressions remain available. |
| R11/R12; L3 | Review evidence gate: report checkpoint/visual/physical scopes separately; reject optical passes inferred from fixtures, or shipped reframing. These are review obligations, not fictitious unit tests. |

## Implementation, findings and bounded acceptance

The user approved learning normal scene variation before Ready, integrating arrival/settlement/rearming, preserving identical-copy scanning, and requiring recorded replay plus physical Start/tap/drop acceptance. The explicit additional constraint is that the correction **must not significantly increase overall scanning time**; adding time to every capture is not a casual tradeoff.

Implemented behavior:

1. Low-pass resample each BGRA camera frame before extracting the fixed coarse luminance grid. Select calibrated motion regions using resampled cell centers. Photo, YOLO and crop coordinates remain unchanged.
2. Learn bounded scene variation during the **existing eight-frame warmup**. Substantial startup movement restarts learning rather than becoming unlimited noise allowance. Show **Preparing** until a valid learned reference exists, then **Ready**. Keep Stop and the manual shutter available during Preparing.
3. Feed actual adjacent stability into the burst state machine alongside noise-adjusted motion. An unsettled candidate must remain eligible; do not apply a later veto after the state machine has consumed settlement.
4. Continue owned-sample collection during accepted settlement/photo/crop work, and prepare the next reference concurrently. Validate preparation variation against the destination calibrated region, including first calibration. Reject excessive preparation movement; preserve bounded learned variation through short/quiet preparation. Identical-copy arrival motion remains eligible even if the final image looks the same.
5. Add **no new fixed per-card delay or compulsory post-capture learning window**. Readiness is session-tagged and independent of recognition completion. Filtering adds CPU work; throughput equivalence must not be inferred merely from the absence of a timer.
6. Keep DEBUG-only, opt-in `STATION_SAMPLE_PROFILE=1` diagnostics for sampler duration and busy-frame drops. These diagnostics do not record camera images.

Decision rationale: [ADR 0008](../decisions/adr-0008-station-motion-reference.md). Detailed logs remain in the optional local `tmp/capture-noise-correction/` packet.

### Important failures and findings to retain

- The withdrawn image-stability/translation filtering regression could discard a valid arrival **after** `MotionBurstDetector` emitted settlement. Exact repeated synthetic final frames passed while ordinary low image noise blocked captures. Restoring valid arrivals exposed existing Start/tap false captures; that rollback was recovery, not a complete shake-rejection fix.
- An initial learned min/max band also failed intermittently. One unchanged trace build appeared successful, but shifting the start of the same stationary recording reproduced a false capture through the real tracker. A successful single physical run or fixed replay start was insufficient evidence.
- Sparse point sampling aliased fine stationary image/lighting variation into motion. In the local sampled-reference/burst probe, 44 of 60 stationary learning starts produced false captures; region-averaged samples produced none. The real tracker regression failed at a six-second start offset before low-pass sampling. The final actual tracker replay covers **60 stationary start phases** and passes.
- Completion haptics and focus/exposure changes were investigated as possible contributors. They were **not established as the cause** of all prior false captures. Do not promote that hypothesis to a finding.
- The process failed to evaluate a local icon request against all navigation siblings, to cover noisy/phase-dependent inputs, and to keep source/synthetic review conclusions separate from physical workflow acceptance. For future changes: compare all sibling states before recommending a local style exception; reproduce the reported failure before changing production; include noise, repeated/identical arrivals and shifted recording starts; report native presentation, automated behavior, optical quality and physical reliability at their actual evidence scopes. Source review or checklist completion cannot substitute for hardware evidence.

Detailed prior process analysis remains in the optional local `tmp/capture-trigger-recovery/process-findings.md`. Failed physical acceptance and replay logs remain in the correction artifacts; later success does not erase them.

### Final evidence and limits

- **Bounded physical acceptance passed**, on the connected iPhone 17 Pro in Station at **1.5×**: Start with a resting card, two light taps, three rapid drops including identical copies, and empty-tray Start plus first arrival produced four intended captures with no reported extras or misses. The user found capture-to-Ready timing OK but explicitly noted the small sample.
- Final iOS suite: **717 executed, 716 passed, one existing named-accessibility-action skip, zero failures**. Includes the 60 stationary starts, both local recordings, noisy settlement, identical copies, bounded rearming, calibration transitions and readiness/lifecycle cases. API tests: **251 passed**, one existing dependency warning. SwiftLint: zero violations. Simulator and device builds passed. Two focused native UI checks for Preparing controls and active zoom passed and were reused after sampler-only changes.
- Controlled original-detector replay arrivals were 14.0333, 19.9667 and 25.6333 seconds, plus three false Start captures. Final arrivals were 13.9, 19.8667 and 25.6 seconds: exactly three intended captures, 133/100/33 ms earlier. The second recording retained exactly three arrivals. Serialized replay does **not** establish live throughput; these tests inject model boxes and simulate accepted preparation.
- On-device sampler cost over 1,103 frames: median **8.65 ms**, p95 **12.67 ms**, maximum **26.42 ms**, all within the 33.33 ms frame interval. Eight busy-frame drops occurred during accepted preparation; none occurred while watching for an arrival.
- Four physical trigger-to-rearm intervals were **1.533, 1.261, 1.190 and 1.376 seconds**, median **1.3185 seconds**, versus an earlier uncontrolled three-shot median **1.186 seconds**. **Equivalent overall throughput remains unproven.** Preserve both the user-acceptable small-sample result and this measured uncertainty; do not claim that scanning speed is unchanged. Sustained throughput/thermal behavior and other stands, zooms and lighting remain unverified.
- Two user-authorized 30-second camera recordings remain **local, gitignored review artifacts**. No movie is committed or uploaded. Temporary recording hooks were restored byte-for-byte and removed; the final normal non-recording app was installed and relaunched without profiling. Optional recording-backed tests explicitly skip when the local movies are absent; portable regressions remain in the suite.
- Optical binder/stack quality, broader hardware fallback, device VoiceOver/Reduce Transparency and the unrelated existing iOS26 tablet rotation limitation are not resolved by this trigger correction. Reuse relevant earlier evidence rather than repeating unrelated exploration or validation.

## Earlier evidence retained at its actual scope

- Lifecycle `f55590f`: 692 logic passes/one existing skip; 10 UI passes/two expected skips; physical iPhone 17 Pro preview ownership/live handoff test passed over five mode handoffs. iOS18 tablet portrait/both landscapes passed. iOS26 tablet landscape viewport assertion failed and reproduced on pre-change source; unrelated baseline limitation, not fixed or revalidated by trigger work.
- Recognition redesign: 693 logic passes/one existing skip at that stage; native stacked-notice independent expiry, geometry, cancellation/preference/recovery checks and phone/AX/tablet screenshots inspected. Later source checks preserve shimmer/Reduce Motion; no claim of a subjective timing benchmark.
- Independent full native finish review after lifecycle screenshot recapture: **ship at that scope**, using a fresh general-purpose reviewer in place of unavailable named Impeccable role. Prior two-contrast-fix ship verdict was only those fixes. User rejection triggered renewed full review; neither verdict proves optical quality. All-five-blue correction had targeted native test/screenshots.
- Latest counts above supersede earlier suite totals, not earlier failed acceptance. Raw logs/xcresults/screenshots remain optional local review evidence; their summaries here survive a fresh checkout.

## Workflow findings and retention decision

The missing brief updates violated an existing maintenance instruction. Worktree skill
updates were present, but no feature-build body read was found during ordinary
follow-ups; discovery pointed at older main-checkout copies. That mismatch was verified,
not established as the sole runtime cause. The initial correction added continuation-wide
maintenance, worktree skill provenance and stale-record review gates. Five fresh cases
passed; the small old-instruction baseline also passed, so controlled wording superiority
and universal enforcement were not claimed.

A separate gap remained: that corrected workflow still saved approvals into ignored tmp
and required synchronization without tracked retention. The actual approved record was
absent from the PR. A fresh read-only baseline confirmed this was permitted explicitly,
though the agent recommended tracked preservation as its own judgment. The retention
correction now requires tracked approval/contract/evidence summaries before dependent
implementation or legacy completion, verifies inclusion and essential links, and makes
ignored-only approvals a read-only correctness finding. Drafts/private evidence stay
local. Original local history is preserved; old brief paths forward here. No cleanup,
private recording publication, product redesign or new physical validation is authorized.

Retention verification: three fresh isolated cases passed (legacy completion,
approved design handoff at a requested tmp path, and read-only retention review).
Actual staged records, forwarding pointers, preserved source history and unchanged
private files were inspected. All three skill-format validators, tracked-link,
non-ignore/index-retention and whitespace checks passed. Independent review found
no blockers across all nine changed files. These bounded cases do not establish
universal instruction compliance; application lint/runtime checks are N/A here.

[AGENTS.md](../../AGENTS.md#approved-brief-retention) is canonical policy;
[workflow](../feature-workflow.md) and the explicit feature skills route to it.
Architectural trigger rationale is in [ADR 0008](../decisions/adr-0008-station-motion-reference.md).
Current camera policy history is in [ADR 0007](../decisions/adr-0007-auto-scan-focus-and-close-up-camera.md).

## Review and continuation

Ready for manual review through PR #139, not merged. Worktree/branch/local evidence
remain retained. Reuse the verification above for these documentation-only changes;
no new app build, runtime test or physical acceptance claim follows from retention.
Inspect with `git show --stat HEAD` and this record. To exercise the app, open
`apps/ios/MTGScanner.xcworkspace`; relevant checks are `make ios-test`, `make ios-lint`
and the CaptureControlsTests filter documented in iOS guidance. Those commands were
not rerun for the retention correction.

Future approved changes update this record and affected test rows before dependent
work. Preserve its repository-relative path in PRs and absolute path in local handoffs.
The retention change's format/link checks, fresh behavioral checks and independent
review are reported in the PR and local handoff; these do not replace product evidence.
