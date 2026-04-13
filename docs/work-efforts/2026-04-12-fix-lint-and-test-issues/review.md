# Review: Fix lint and test issues

**Reviewed by:** big-pickle
**Date:** 2026-04-12

## Summary

**What was requested:** Fix lint issues in Swift and Python code, and improve test isolation to prevent .env configuration leakage in API tests.

**What was delivered:** Fixed SwiftLint violations through code refactoring and extraction. Improved Python test isolation with dotenv disabling at module import. Added new test files for refactored code.

**Deferred items:** none

## Code Review Checklist

### 1. Correctness

**Result:** pass

All lint issues resolved. Test isolation properly implemented - dotenv is disabled before any imports that could load it. Refactored code maintains original behavior - extracted classes/enums have identical implementations.

### 2. Simplicity

**Result:** pass

Code organization improved with MARK-based extensions. Functions extracted to appropriate helper methods. NMS logic extracted to `applyNMS(to:)` and `applyContainmentSuppression(to:)` for clarity. No unnecessary abstractions introduced.

### 3. No Scope Creep

**Result:** pass

Changes limited to lint fixes and test improvements. No new features added. No "while I'm here" changes. Extracted types moved to separate files but maintain identical behavior.

### 4. Tests

**Result:** pass

New tests added for refactored code:
- `test_settings_bootstrap.py` - validates dotenv isolation
- `RectangleFilterNMSTests.swift` - 155 lines testing NMS logic
- `ScanYOLOSupportValidationTests.swift` - 93 lines testing YOLO validation

All 228 existing tests continue to pass.

### 5. Safety

**Result:** pass

No force unwraps in new Swift code. No unhandled exceptions in Python. Thread safety preserved in extracted `PhotoCaptureHandler` (maintains `@unchecked Sendable`). Environment variable clearing properly scoped.

### 6. API Contract

**Result:** not applicable

No API changes - this was an internal refactoring and test improvement task.

### 7. Artifacts and Observability

**Result:** pass

Debug logging in `CardDetectionEngine` extracted to dedicated `logScanFrame()` method but preserved for DEBUG builds. No silent failures introduced.

### 8. Static Analysis

**Result:** pass

`make lint` passes (mypy + SwiftLint). `make api-test` passes (228/228). No new lint suppressions added without justification. Removed unnecessary `// swiftlint:disable` comments.

## Verification Results

```
make api-test
============================= test session starts ==============================
platform darwin -- Python 3.13.12, pytest-9.0.3, pluggy-1.6.0
...
services/api/tests/test_settings_bootstrap.py .                          [ 98%]
...
============================= 228 passed in 13.21s =============================

make api-lint
Running mypy...
Success: no issues found in 25 source files
mypy passed.

make ios-lint
Running SwiftLint...
Linting completed without violations.
```

## Notes

- Work completed across 5 commits: lint/test fixes, test environment setup, import reordering, settings isolation enhancement, and dotenv validation
- The dotenv isolation approach using `Settings.model_config["env_file"] = ()` is a pydantic-settings pattern that prevents Settings from reading .env files after module import
- Swift extraction of `PhotoCaptureHandler` and `ScanYOLOSupport` improves maintainability and reduces file complexity
- NMS tests added to `RectangleFilterNMSTests.swift` fill a gap in test coverage for the extracted logic
