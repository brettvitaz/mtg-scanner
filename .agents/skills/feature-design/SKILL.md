---
name: feature-design
description: Use when the user explicitly invokes feature-design with a feature request for this repository, before production changes.
---

# Feature design

The user's feature request follows this skill. Agree on a design with the user, get explicit approval, and save the approved design as a brief that `feature-build` implements. Do not change product code in this phase.

## Rules

- When you say you will do a step, make the tool call in the same turn. Do not end a turn after only announcing a step.
- Work only in the current worktree. Do not inspect other branches, worktrees, or earlier attempts without explicit user authorization. Read only specifically authorized external artifacts; transfer them into the task handoff.
- Resolve repository skill provenance and maintain any designated active brief per `AGENTS.md`. Root instructions already read from this task worktree need no repeat; instructions supplied from another checkout do not establish this worktree's version.
- Every statement about how the current code behaves must cite a `file:line` you read in this session. Label anything you have not checked as "unverified".
- Ask questions about what the user will see or do. Do not phrase questions in terms of APIs, types, or files. Implementation choices are yours to make; report them in the design.
- Do not ask again about settled user decisions in the requirements record.

## Steps

Create a todo list with one item per step before you start, and keep it updated.

1. Read these in full, as whole files with no line ranges:
   - The nested `AGENTS.md` for each subsystem the feature touches (`apps/ios/AGENTS.md`, `services/api/AGENTS.md`).
   - The `.agents/rules/` files that the root `AGENTS.md` routes to for those subsystems, plus `.agents/rules/testing.md`.
   - `PRODUCT.md`.
2. Read the code the feature will change.
3. For UI work, load [Impeccable](../impeccable/SKILL.md) once per session, run its setup with the actual target, and follow [shape](../impeccable/reference/shape.md). For native iOS read [ios](../impeccable/reference/ios.md); capture surfaces use Operate mode. Classify refinement versus replacement: a rejected overall treatment routes through [new-work](../impeccable/reference/new-work.md)'s applicable direction/concept process, while a narrow settled fix inherits the existing world. Shape returns after direction selection, before contracts, persistence, or implementation; the builder resumes those steps.
4. Ask only material unresolved questions about what users see or do. For UI work use shape's cadence and the structured question mechanism actually available in this harness; otherwise ask in plain text and wait. A precise request may need only compact confirmation. For non-UI work ask only what the request leaves unsettled. Record decisions without repeating settled questions.
5. Present the design with these sections:
   - **Requirements**: one authoritative record, inline here or at a linked path. Use stable IDs (R1, R2…), source/quote, kind (user decision, implementation choice, assumption, open question), status, and supersedes/superseded-by IDs. Behavior and tests reference these IDs rather than maintaining a competing list. Preserve explicit user decisions; later corrections override older text. Resolve contradictions in affected sections. For example, “use the same lens” supersedes “preserve separate lens selection”; “protect Station focus” constrains the shared policy, not a return to separate lenses.
   - **Behavior**: what users see and do, keyed to effective requirement IDs.
   - **Selected direction** (UI): visual authority and selected concept/reference paths and versions, approval evidence, scope (refinement/replacement), visitor mode, native feasibility and unresolved risks. Describe whole-screen composition, control hierarchy, material/background transitions, meaningful sizing/spacing, open overlays, transitions and accessibility. A component list or browser sketch alone does not establish native fit.
   - **Code changes**: files and what changes in each, with `file:line` evidence for every claim about existing code.
   - **Test map**: for each effective requirement ID, the test that will fail if that behavior breaks, and the code change that would make it fail (for example, "remove the reset in `clearCount()`"). If no code change the test can reach would make it fail, it is not a test for that behavior; find another. For purely visual behavior, name the snapshot route instead.
   - **Verification**: separate behavioral tests (Test map), rendered checks, independent visual judgment, and physical acceptance. For UI, name exact states and acceptance criteria, snapshot routes per `apps/ios/AGENTS.md`, shipped device classes, appearances and relevant text sizes. Check route entry preserves the intended state, including open overlays. Name the independent Impeccable finish review obligation and hardware checks still owed; visual approval does not prove camera selection, framing or sharpness.
   - **Docs**: files to update.
   - **Additions I propose (need approval)**: anything not covered by settled user decisions. Write "None" if empty.
   - **Unverified**: claims you have not checked against the code.
6. Obtain explicit approval for the selected design and record what version was approved. Incorporate corrections without reopening settled decisions; approval of a picture is evidence for that direction, not proof of hardware behavior. Do not change production code in this phase.
7. Save the approved brief to `tmp/feature-briefs/<short-name>.md`. Include the original request verbatim and all approved sections above, including additions, unverified claims, approval status/source and artifact paths. Keep one authoritative record per decision. Designate the absolute active brief path in the handoff so later ordinary follow-ups retain its maintenance obligation. Transfer gitignored briefs, temporary/external screenshots and sidecars into a handoff accessible to the next session/worktree, with explicit source/destination paths; verify files exist. Report missing artifacts, never infer approval from absence. Do not create a direction contract here. Give the absolute brief and artifact paths and the new-session command: `/skill:feature-build <brief path>` in pi, or `$feature-build` with that path in Codex.
