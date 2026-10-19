# ADR 0008: Station scene variation and integrated settlement

Status: Accepted; validation scope and limits below.

## Context

Station motion based on isolated sparse luminance pixels can interpret fine image or
lighting variation as an arrival. An after-settlement stability veto also consumed
valid candidates before capture, producing missed or delayed drops. Identical-copy
scanning requires preserving actual arrival motion even when the final card looks
the same. Additional fixed per-card waiting is unacceptable.

## Decision

Low-pass resample BGRA video onto the existing coarse full-frame grid before taking
luminance samples. Calibrated motion regions select resampled cell centers; photo,
YOLO and crop coordinates remain unchanged. Learn bounded per-pixel variation during
the existing burst warmup and show Preparing until the reference is ready.

Feed noise-adjusted motion and actual adjacent stability into the burst state
machine together. Settlement must retain an unsettled candidate rather than let a
later veto silently discard an already consumed event. YOLO validation still gates
accepted arrivals.

Continue owned-sample collection during accepted settlement/photo/crop preparation.
Rearm from those samples without another compulsory learning period. Reject excessive
preparation movement using the destination motion region, preserve prior noise widths
through quiet preparation, and bound repeated/short rearming. Queue confinement and
session-tagged readiness protect lifecycle changes.

## Consequences and validation

No timer or extra per-card wait is introduced. Filtering adds computation, requiring
physical sampler-cost and busy-frame-drop measurement. Debug-only
`STATION_SAMPLE_PROFILE=1` provides those logs without image recording.

Local recordings cover real arrivals, identical copies, Start/tap behavior and
stationary replay from shifted warmup phases. A single successful physical run or
one fixed replay start is insufficient acceptance. Recordings remain local and are
not committed; optional replay tests explicitly skip when they are absent. Portable
pattern, noisy-settlement, rearming and lifecycle regressions remain in the suite.
The amended sampler passed the physical 1.5× stand workflow: Start, two light taps,
three rapid drops including identical copies, and an empty-tray Start plus first
arrival produced four intended captures with no reported extras or misses.
Sampler median/p95 cost was 8.7/12.7 ms; no busy frames were dropped while watching.
Eight busy drops occurred during accepted capture preparation. Four capture-to-rearm
intervals ranged 1.19–1.53 s (median 1.32 s), versus an earlier small uncontrolled
sample median 1.19 s. The user found timing acceptable but noted the sample was small.
This establishes bounded functional acceptance, not unchanged throughput or universal
reliability across stands, zooms and lighting.
