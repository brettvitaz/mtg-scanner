# Code Review

When reviewing code — whether self-reviewing before commit or evaluating changes — check each of these criteria. If any criterion fails, the change should be fixed before merging.

## 1. Correctness
- Does the code do what the spec or task description says?
- Are edge cases handled (empty inputs, boundary values, nil/optional paths)?
- Are there logic errors, off-by-one errors, or incorrect math?

## 2. Simplicity
- Are functions short (< 30 lines preferred, < 50 max)?
- Is nesting depth ≤ 3 levels?
- Is there duplicated logic that should be extracted?
- Are there unnecessary abstractions, protocols, or generics?
- Could any part be simplified without losing correctness?

## 3. No scope creep
- Does the code ONLY implement what was requested?
- No parameters, protocols, or abstractions added "for future use."
- No dead code, commented-out code, or TODO placeholders.
- No "while I'm here" cleanup of unrelated code.

## 4. Tests exist and are meaningful
- Does every new public method have at least one test?
- Do tests exercise real code paths?
- Are edge cases tested?
- Would the tests fail if the implementation were broken?

## 5. Safety
- **Swift**: No force unwraps in production code. No retain cycles (check closures capturing `self`). Correct `@MainActor` / queue usage.
- **Python**: No unhandled exceptions in service code. No raw `os.environ` reads. Settings via Pydantic.
- **Both**: Thread safety for shared mutable state. No secrets or credentials in code.

## 6. API contract
- Response schema unchanged unless the task explicitly requires it.
- Schema examples updated if the contract changed.
- Mock provider behavior still aligned with contract.

## 7. Artifacts and observability
- Recognition/detection changes still produce useful debug artifacts.
- Validation metadata recorded for debugging and eval.
- No silent failures — errors are logged or surfaced.
