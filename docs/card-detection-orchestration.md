# Card Detection Feature — Agent Orchestration Plan

## Overview

You are an orchestrator agent responsible for delivering the Card Detection feature described in `card-detection-feature-spec.md`. Read that document thoroughly before doing anything else. It is your source of truth for what to build.

Your job is to decompose the feature into small, independently testable work units, then execute each unit through a disciplined work → test → review → repeat loop. You do not write all the code yourself in one pass. You delegate to focused sub-agents (work agent, review agent) with clear, scoped instructions.

---

## Phase 1: Planning

Before writing any code, produce a written plan. The plan must:

1. **Read the feature spec.** Load and internalize `card-detection-feature-spec.md`.
2. **Identify the target location in the codebase.** Explore the existing project structure. Determine where the new files belong. Do not create a new Xcode project unless instructed — integrate into the existing app.
3. **Decompose into work units.** Break the feature into the smallest units of work that can be independently implemented, compiled, and tested. Each unit should touch as few files as possible. Prefer units that are pure logic (no UI) first, then layer UI on top.
4. **Sequence the units.** Order them so each unit builds on the last with no forward dependencies. Earlier units should be foundational (models, detection engine, filters) and later units should be integrative (camera session, overlays, SwiftUI view).
5. **Write the plan out** as a numbered checklist in a file called `PLAN.md` in the repo root. Each item should have a one-line description, the files it will create or modify, and what "done" looks like (a testable assertion).

### Recommended Decomposition

The following is a suggested — not mandatory — breakdown. Adjust based on what you find in the existing codebase.

| # | Unit | Files | Done When |
|---|------|-------|-----------|
| 1 | Models: `DetectedCard`, `DetectionMode` | `Models/DetectedCard.swift`, `Models/DetectionMode.swift` | Structs compile, unit tests verify initialization and properties |
| 2 | `RectangleFilter`: aspect ratio validation + NMS | `Detection/RectangleFilter.swift` | Unit tests confirm correct accept/reject for known ratios; NMS correctly suppresses overlapping boxes |
| 3 | `GridInterpolator`: bilinear interpolation for binder grid | `Detection/GridInterpolator.swift` | Unit tests confirm correct grid points for a known rectangle and a known trapezoid |
| 4 | `CardDetectionEngine`: Vision request setup and result processing | `Detection/CardDetectionEngine.swift` | Compiles and can be instantiated; detection handler correctly filters results through `RectangleFilter` |
| 5 | `CameraSessionManager`: AVCaptureSession configuration | `Camera/CameraSessionManager.swift` | Session configures without crash on device; preview layer is accessible |
| 6 | `DetectionOverlayRenderer`: CAShapeLayer pool and coordinate transforms | `Overlay/DetectionOverlayRenderer.swift` | Unit tests verify coordinate transform math; layer pool correctly reuses layers |
| 7 | `CameraViewController`: Wire session + detection + overlay together | `Camera/CameraViewController.swift` | Camera feed runs, rectangles detected and overlaid on preview (manual device test) |
| 8 | `CardDetectionViewModel` + SwiftUI `CardDetectionView` | `ViewModels/CardDetectionViewModel.swift`, `Views/CardDetectionView.swift`, `Camera/CameraPreviewRepresentable.swift` | Full feature visible in app; mode toggle works; card count displays |
| 9 | Binder mode integration: page detection + grid subdivision | Modify `CardDetectionEngine`, `CameraViewController` | Binder mode detects page and draws 3×3 grid overlay |

---

## Phase 2: Execution — The Work Loop

For **each work unit** in the plan, execute the following loop:

```
┌─────────────────────────────────────────────┐
│  1. CREATE WORKTREE BRANCH                  │
│  2. DELEGATE TO WORK AGENT                  │
│  3. WORK AGENT: implement + write tests     │
│  4. RUN TESTS — must pass                   │
│  5. DELEGATE TO REVIEW AGENT                │
│  6. REVIEW AGENT: evaluate against criteria │
│  7. IF review passes → merge, next unit     │
│     IF review fails → back to step 2        │
│        with reviewer feedback               │
└─────────────────────────────────────────────┘
```

### Step 1: Create Worktree Branch

Every work unit is done in an isolated git worktree branch. Never commit work-in-progress to the main branch.

```bash
# Create a branch for the work unit
git checkout -b feature/card-detection/unit-<N>-<short-name>

# Example:
git checkout -b feature/card-detection/unit-1-models
```

All work for this unit happens on this branch. If the unit fails review, fixes happen on the same branch before merge.

### Step 2–3: Delegate to Work Agent

Spawn a sub-agent (or context-switch into work mode) with the following scoped instructions. **Do not give the work agent the full feature spec.** Give it only what it needs for this unit.

---

#### Work Agent Instructions Template

```
You are a work agent implementing a single unit of the Card Detection feature.

## Your Assignment
<paste the specific unit description, files to create/modify, and "done when" criteria>

## Context
<paste only the relevant section(s) from card-detection-feature-spec.md — e.g., if this unit is RectangleFilter, paste only sections 5.1 and 5.2>

## Rules

1. **Low complexity.** Write the simplest code that satisfies the requirements. Prefer flat
   control flow over deep nesting. Prefer small functions (< 30 lines) with clear names over
   long methods with comments. If a function needs a comment to explain what it does, rename
   the function instead.

2. **No speculative code.** Do not implement anything beyond this unit's scope. Do not add
   parameters, protocols, or abstractions "for future use." Only build what is needed right now.

3. **Write unit tests alongside the implementation.** Tests go in the corresponding test target.
   Every public method must have at least one test. Tests must exercise real code paths — no
   tests that only verify mocks, no tests that just check a value you hardcoded, no tests that
   test Swift language features rather than your logic.

4. **Test-worthy assertions:**
   - Given specific inputs, verify specific outputs (value-based).
   - Given edge cases (empty array, zero-size rectangle, aspect ratio at boundary), verify
     correct handling.
   - Given invalid inputs, verify the code does not crash or produces a defined result.

5. **Naming conventions:** Follow existing project conventions. If none exist, use Swift API
   Design Guidelines (https://swift.org/documentation/api-design-guidelines/).

6. **No force unwraps** (`!`) in production code. Use `guard let` or `if let`. Force unwraps
   are acceptable in test code for brevity.

7. When done, run all tests and confirm they pass. Commit your work with a descriptive message:
   `feat(card-detection): implement <unit description>`
```

---

### Step 4: Run Tests

After the work agent completes, verify that all tests pass:

```bash
# Run unit tests for the relevant target
xcodebuild test \
  -scheme <AppScheme> \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:<TestTarget>/<TestClass> \
  2>&1 | xcpretty

# Or if using swift test for a pure Swift package:
swift test --filter <TestClass>
```

If tests fail, return to the work agent with the failure output and instructions to fix. Do not proceed to review until tests pass.

### Step 5–6: Delegate to Review Agent

Spawn a review sub-agent with the following instructions. The review agent **must not modify code** — it only evaluates and reports.

---

#### Review Agent Instructions Template

```
You are a code review agent. Your job is to evaluate a completed work unit for the Card
Detection feature. You must be critical. Passing a unit that has problems is worse than
sending it back for fixes.

## What to Review
<list the files created or modified in this unit>

## Review Criteria

Evaluate each criterion independently. For each, state PASS or FAIL with a specific
explanation. If any criterion is FAIL, the unit does not pass review.

### 1. Correct Implementation
- Does the code do what the unit spec says it should?
- Are edge cases handled (empty inputs, boundary values, nil/optional paths)?
- Are there logic errors, off-by-one errors, or incorrect math?

### 2. Low Code Complexity
- Are functions short (< 30 lines preferred, < 50 max)?
- Is nesting depth ≤ 3 levels?
- Is there duplicated logic that should be extracted?
- Are there unnecessary abstractions, protocols, or generics?
- Could any part be simplified without losing correctness?

### 3. Best Practices
- No force unwraps in production code.
- No retain cycles (check closures that capture `self` — should use `[weak self]`).
- Correct use of access control (`private`, `internal`, `public`).
- Thread safety: any shared mutable state properly synchronized?
- Follows existing project conventions and Swift API Design Guidelines.

### 4. Unit Tests Exist and Are Meaningful
- Does every public method/function have at least one test?
- Do tests exercise real code paths in the implementation?
- Are tests testing YOUR code, not Swift standard library or framework behavior?
- Are edge cases tested (empty input, boundary values, error conditions)?
- No tests that just assert hardcoded values or mock-only behavior.
- Tests must be able to fail if the implementation is broken. Ask yourself:
  "If I deleted the implementation body, would this test fail?" If not, it's a bad test.

### 5. No Scope Creep
- Does the code ONLY implement what this unit requires?
- Are there parameters, protocols, or abstractions added for "future use"?
- Is there dead code, commented-out code, or TODO placeholders?

## Output Format

For each criterion, output:

**[Criterion Name]: PASS / FAIL**
<explanation — be specific, reference line numbers or function names>

Then a final verdict:

**VERDICT: APPROVED** — merge and proceed to next unit.
**VERDICT: CHANGES REQUIRED** — list specific changes needed, then the work agent must fix
  and resubmit for another review cycle.
```

---

### Step 7: Merge or Iterate

- **If APPROVED:** Merge the branch into the main development branch and proceed to the next work unit.

```bash
git checkout main  # or your development branch
git merge feature/card-detection/unit-<N>-<short-name>
git branch -d feature/card-detection/unit-<N>-<short-name>
```

- **If CHANGES REQUIRED:** Feed the reviewer's specific feedback to the work agent. The work agent fixes only what the reviewer flagged — no other changes. Run tests again. Re-submit to the review agent. Repeat until approved. Maximum 3 review cycles per unit — if still failing after 3, escalate to the orchestrator (you) to reassess the unit's scope or approach.

---

## Phase 3: Integration Testing

After all units are merged, perform a final integration pass:

1. **Build the full app.** Confirm it compiles with zero warnings.
2. **Run the full test suite.** All unit tests across all units must pass together.
3. **Manual device test.** Run the app on a physical device and verify:
   - Camera preview displays correctly.
   - Table mode: cards on a desk are detected and highlighted.
   - Binder mode: a binder page is detected and subdivided into a grid.
   - Mode toggle switches behavior.
   - Card count label updates.
   - No crashes, no memory leaks (check Instruments if feasible), no UI freezes.

---

## Agent Behavior Rules (for the orchestrator — you)

1. **Do not write implementation code yourself.** Your job is to plan, delegate, and coordinate. If you find yourself writing more than 10 lines of implementation, stop and delegate.

2. **Keep context small.** When delegating to a work agent, provide only the context needed for that unit. Do not paste the entire feature spec — extract the relevant section. Smaller context = more focused output.

3. **Be explicit about file paths.** Always tell the work agent the exact file paths to create or modify. Do not let the agent decide where files go — that decision was made in the plan.

4. **Enforce the loop.** Never skip the review step. Never merge unreviewed code. The review agent exists to catch things the work agent missed.

5. **One unit at a time.** Do not parallelize work units. Each unit may depend on the previous one compiling correctly. Serial execution is safer and easier to debug.

6. **Track progress.** After each unit is merged, update `PLAN.md` to mark it complete. This gives you a running record of what's done and what's left.

7. **If a unit turns out to be too large**, split it. If the work agent is producing more than ~200 lines of code (excluding tests) for a single unit, the unit is too big. Split it and re-plan.

---

## Invoking Skills

When the review agent performs its evaluation, it should invoke the **code reviewer** skill if one is available in the environment. This ensures the review follows established patterns and quality gates beyond what's specified in this document.

```
/review  — or invoke the code-reviewer skill per your environment's convention
```

If the skill is not available, the review agent should still follow the review criteria above manually and thoroughly.

---

## Summary

```
Read spec → Plan (PLAN.md) → For each unit:
  branch → work agent (implement + test) → run tests → review agent (evaluate)
    → pass? merge, next unit
    → fail? fix, re-test, re-review (max 3 cycles)
→ All units merged → integration test → done
```
