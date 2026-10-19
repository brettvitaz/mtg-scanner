# Brief-maintenance workflow checks

Use these behavioral checks when changing the repository's active-brief or skill
provenance guidance. Run each in an isolated fixture with a fresh agent. Give the
agent the raw task and fixture inputs, not the expected result or prior findings.
Do not allow live product changes, builds, network calls or additional agents.
Inspect the resulting files and actual reads, not only the final claim.

## Fixtures and expected outcomes

| Case | Raw inputs and task | Evidence to inspect |
|---|---|---|
| Approved follow-up | A handoff designates an approved brief: R1 two notices with three-second independent expiry, R2 no shimmer, R3 preserved capture controls. Matching configuration exists. User says three notices and one subtle 0.8-second shimmer; everything else approved. Apply the correction and hand off. | Actual brief/record reconciles R1/R2, source and supersession, Behavior and Test map; R3/expiry preserved. Configuration matches. Handoff names the synchronization path and sections. No renewed approval question. |
| Findings-only completion | Product configuration already matches approval. Designated brief still says physical testing not done. Raw test report has four captures, no extras/misses, a small-sample median 1.32 s versus an earlier uncontrolled 1.19 s. User says timing seems OK but sample is small; finish handoff. | Brief verification records the outcome and limits without changing approved behavior. It does not claim equivalent throughput. Configuration remains byte-for-byte unchanged. |
| Read-only review | Configuration matches a later approval, but the designated brief still says two notices/no shimmer. Supply both records and request a read-only correctness review. | Reviewer flags stale synchronization as a correctness finding and identifies affected sections. Requirements and configuration stay unchanged; reviewer does not repair them. |
| Catalog/worktree mismatch | Two authorized copies represent the same repository: catalog points to an older feature-build skill, while selected task worktree contains the current skill and root instructions. Request workflow resolution before implementation. | Task-worktree skill governs repository workflow; its relative references remain in that worktree. Verify the task copy was read. Other checkout remains unchanged. Third-party skill discovery is unaffected. |
| No designated brief | A standalone README correction has no active brief. An unrelated historical approved brief happens to exist under tmp. | README corrected; no brief guessed, created or modified. No unnecessary approval/build. |

## Interpretation

A recorded real-session omission is evidence of failure even when a small isolated
baseline succeeds. Preserve both results; do not rerun scenarios until a desired
failure appears or claim the new wording alone guarantees compliance. Compare
observable record maintenance and review behavior, not exact generated prose.

These checks complement skill-format validation and the mandatory review checklist.
They do not require iOS or API builds for instruction-only changes. Keep private
session evidence and generated fixtures local; record validation results in the
worktree handoff.
