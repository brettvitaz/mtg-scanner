# Review: [FILL: same title as request.md]

**Reviewed by:** [FILL: agent name or model]
**Date:** [FILL: YYYY-MM-DD]

## Summary

**What was requested:** [FILL: one-sentence summary from request.md]

**What was delivered:** [FILL: one-sentence summary of what actually shipped]

**Deferred items:** [FILL: anything from the request that was not completed, with reason — or "none"]

## Code Review Checklist

Evaluate each criterion against the changes made. State pass or fail with brief evidence.

### 1. Correctness

**Result:** [FILL: pass | fail]

[FILL: does the code do what the request asked? edge cases handled?]

### 2. Simplicity

**Result:** [FILL: pass | fail]

[FILL: functions < 30 lines? nesting ≤ 3 levels? unnecessary abstractions?]

### 3. No Scope Creep

**Result:** [FILL: pass | fail]

[FILL: only requested changes? no "while I'm here" additions? no dead code?]

### 4. Tests

**Result:** [FILL: pass | fail]

[FILL: new/changed code has tests? tests exercise real paths? tests would fail if implementation broke?]

### 5. Safety

**Result:** [FILL: pass | fail]

[FILL: no force unwraps (Swift), no unhandled exceptions (Python), no secrets in code, thread safety correct?]

### 6. API Contract

**Result:** [FILL: pass | fail | not applicable]

[FILL: response schema unchanged unless explicitly requested? mocks aligned?]

### 7. Artifacts and Observability

**Result:** [FILL: pass | fail | not applicable]

[FILL: debug artifacts still produced? no silent failures?]

### 8. Static Analysis

**Result:** [FILL: pass | fail]

[FILL: linting passes? no new suppressions without justification?]

## Verification Results

[FILL: paste or summarize the output of verification commands — tests, builds, manual checks]

## Notes

[FILL: anything else the reviewer or next agent should know — or "none"]
