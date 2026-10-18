# Rework instructions: Impeccable across feature design and build

Date: 2026-10-18. Status: proposed skill changes for a future implementation task.
The applicable skills have not been modified by this document.

## Which workflow needs correction?

Both `feature-design` and `feature-build`, and specifically their handoff. Keep the
two phases and explicit design approval. Carry Impeccable's design evidence and
review obligations across that boundary. Align `feature-review` so that its code
review does not imply that visual or hardware acceptance has occurred.

A fresh session can reduce accumulated context, but it does not correct missing
handoff requirements. The desired workflow is:

1. Discover and record current requirements.
2. Shape and select a visual direction using Impeccable where applicable.
3. Approve the design and save a portable handoff.
4. Build that design with Impeccable's implementation guidance.
5. Verify behavior and obtain independent visual finish review.
6. Complete design documentation and hand off outstanding physical checks.

The user already invoked relevant Impeccable skills. Requiring another invocation
or a more elaborate prompt would not address the failure.

## Sources and observed gaps

Read the installed references when performing the skill rework; delegate workflow
details to those references instead of copying a second, drifting implementation:

- [feature-design](../../.agents/skills/feature-design/SKILL.md) already requires
  Impeccable setup and `reference/shape.md` for UI work.
- [feature-build](../../.agents/skills/feature-build/SKILL.md) requires implementation,
  tests, screenshots, self-review, and a commit, but does not explicitly resume
  Impeccable's direction, finish-review, and documentation workflow.
- [feature-review](../../.agents/skills/feature-review/SKILL.md) is intentionally a
  read-only review of implementation correctness and meaningful tests. Its current
  scope does not establish rendered visual quality.
- [Impeccable](../../.agents/skills/impeccable/SKILL.md),
  [shape](../../.agents/skills/impeccable/reference/shape.md),
  [new-work](../../.agents/skills/impeccable/reference/new-work.md),
  [iOS](../../.agents/skills/impeccable/reference/ios.md), and
  [routing](../../.agents/skills/impeccable/reference/routing.md) define the native
  design process, scope distinctions, bounded verification, and finish handoffs.

The recent failure also involved ignoring a live requirements change. No wrapper
gap excuses that: later explicit user instructions take precedence over an older
brief. The reworked skills must make that precedence operational.

## Shared requirements for the skill revisions

### Maintain one current requirements record

Give requirements stable identifiers and record source, status, and supersession.
Separate settled user decisions, implementation choices, assumptions, and open
design questions. Preserve quotes where useful without confusing an agent's
proposal with the user's words.

When the user changes a requirement during build, update the working requirements
and affected brief sections before dependent work. State the concrete consequence.
Do not demand approval again for the requirement the user just supplied. Seek
clarification only for a material unresolved choice; continue independent work.
Return to design for a substantial new visual choice without reopening settled
requirements. Resolve contradictions rather than retaining both instructions.

For this capture task, “use the same lens” supersedes “preserve separate lens
selection.” “Protect Station focus” constrains the shared policy; it cannot silently
restore the superseded instruction.

### Keep the handoff portable and reviewable

Pass file paths to the current brief, requirements record, selected concept or
reference, approval status, required states, and verification plan. Carry actual
artifacts across a fresh-session boundary. Gitignored briefs, external screenshots,
and temporary files require explicit transfer or a clear missing-artifact report.
Do not treat an absent artifact as evidence of approval or inspect unrelated worktrees.

Keep one authoritative record for each decision. Supporting artifacts can be
separate files; the brief must identify them and the specific version approved.

## Changes to feature-design

1. Preserve existing invocation scope, repository rules, evidence requirements,
   and the prohibition on production changes before design approval.
2. Load Impeccable once per session and follow its selected playbook. For native
   iOS, load the iOS reference. Identify Operate mode for the capture surface.
3. Reconcile question cadence with `shape.md`: ask only material unresolved
   questions, use the available structured question mechanism, and do not repeat
   settled decisions. Do not hardcode an obsolete assumption that every harness
   offers interactive questions only in Plan mode.
4. Classify refinement versus replacement. For a rejected overall treatment,
   use the applicable `new-work.md` direction/concept process rather than defaulting
   to another polish pass. Narrow, settled fixes do not need a concept workshop.
5. Make selected direction and native feasibility explicit in the brief. Include
   whole-screen composition, control hierarchy, materials/background transition,
   meaningful sizing/spacing decisions, open overlays, transitions, and accessibility.
   A component list or browser sketch alone is insufficient evidence of native fit.
6. Separate behavioral tests, rendered visual checks, independent visual judgment,
   and physical acceptance. Name exact states and acceptance criteria, not merely
   the number of screenshots to capture.
7. Obtain approval for the selected design, then save the complete handoff. Mark
   unresolved implementation feasibility honestly. An approved visual reference
   does not prove hardware camera behavior.

Respect the phase boundary: Impeccable `shape` stops before a direction contract or
implementation. Save its selected direction and approval evidence in the brief;
the builder resumes the applicable workflow to create/persist implementation
artifacts at the point its installed reference requires. Do not make `shape` perform
steps its own contract forbids.

## Changes to feature-build

1. Before baselines and implementation, reconcile the approved brief with later
   user instructions and verify that required visual artifacts are available.
2. For UI work, load Impeccable and resume the applicable workflow from the selected
   direction. Follow its contract/persistence steps where required. Read
   `craft-floor.md` immediately before UI edits, as the installed skill requires.
3. Preserve the rule that the builder implements the feature itself. Explicitly
   distinguish independent finish review/documentation from delegating implementation.
   Provide reviewers file paths to authoritative inputs instead of retyped summaries
   that can omit a requirement.
4. Verify the actual reported state. An oversized open popup requires opening and
   reviewing that popup. A hosted closed-button geometry test cannot close it.
   Camera consistency requires physical selection and framing evidence, not simply
   equal labels or enum names.
5. Use native simulator screenshots through repository routes and the iOS reference.
   Include all shipped device classes and relevant appearance/text sizes. Browser
   overlays, `live`, `generate`, and the HTML/CSS detector do not verify SwiftUI.
6. Follow Impeccable's bounded builder inspection: one batched inspection, one batch
   of corrections, at most one confirmation round. Then perform the prescribed
   independent finish handoff rather than extending self-polishing indefinitely.
7. Where agents are available, use the finish reviewer required by the installed
   workflow, with fresh context. Supply the user request/corrections, brief, selected
   direction, applicable contract, all required screenshots, platform guidance,
   and quality bar. Verify supported harness routing; do not claim a named shipped
   agent ran when only a generic reviewer was available. If unavailable, follow
   the installed degraded procedure and disclose that limitation.
8. Act on the reviewer's scoped disposition: recapture, rebuild, fix, or ship.
   Follow the reference's correction/review protocol. A list of resolved fixes is
   not automatically whole-surface approval. A user rejection screenshot requires
   a fresh full review with that evidence, not another inline patch and self-pass.
9. Complete the prescribed documentation handoff. Record the finished design in
   `DESIGN.md` and `.impeccable/design.json` when required for an approved system
   change; preserve incumbent files for ordinary extensions per the reference.
10. Keep repository baseline/final checks, meaningful tests, code-review checklist,
    commits, and retained-worktree handoff. Report behavioral results, visual verdict,
    deviations, and hardware limitations separately. Tests alone never establish
    design quality; a visual pass never establishes optical sharpness.

## Alignment changes to feature-review and supporting docs

Keep `feature-review` read-only and focused on correctness. Make its requirement
source the effective brief plus explicit amendments, not only an outdated Behavior
section. Include the visual-review disposition as external evidence with its actual
scope; do not ask a code-only reviewer to certify rendering or hardware behavior.
Missing visual review must remain visible in the handoff.

Update [docs/feature-workflow.md](../feature-workflow.md) to explain both phases,
artifact transfer, visual review, and hardware acceptance. Do not replace the
existing correctness review with a visual review or force UI steps onto backend-only
work. Avoid editing the vendored Impeccable package to compensate for local wrapper
gaps; point the repository skills at its installed references.

## Verification of the revised skills

Use the applicable skill-authoring workflow when implementing these instructions.
Verify behavior with short scenario trials, not only keyword checks in skill files:

| Scenario | Expected outcome |
| --- | --- |
| User changes separate lenses to one shared lens during build | Update effective requirement and brief; assess and implement shared policy without reopening the decision. |
| User reports oversized open zoom popup | Review the real open state; closed-button width test cannot mark the issue resolved. |
| User rejects a shipped screenshot | New full independent finish review includes user evidence; no repeated self-certification. |
| New session reads approved design | Finds selected concept, approval, states, requirements, and visual-review obligations through explicit file paths. |
| UI design direction is rejected wholesale | Applicable replacement/concept workflow precedes more production styling. |
| Native iOS target | Native references and simulator evidence; no web-detector result presented as native verification. |
| Backend-only feature | Existing correctness workflow; no irrelevant visual workshop. |
| Reviewer tools or hardware unavailable | Follow applicable fallback and disclose unverified scope; no invented pass. |

Review each modified skill for contradictory stop/approval rules, duplicated
Impeccable procedures, stale tool assumptions, and ambiguous ownership. Run the
repository documentation checks and report which scenario trials were actually
performed. Preserve all existing worktree, scope, verification, and review rules.

## Scope of this document

This is an implementation specification for future skill revisions, not the revised
skills themselves. The current task creates this document and the companion
[capture findings](capture-design-rework.md); it changes no application behavior,
skill routing, design artifacts, or approval status.
