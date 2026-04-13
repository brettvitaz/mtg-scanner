# Request: Fix lint and test issues

**Date:** 2026-04-12
**Author:** brettvitaz

## Goal

Fix lint issues in Swift and Python code, and improve test isolation to prevent .env configuration leakage in API tests.

## Requirements

1. Fix SwiftLint violations (excessive line lengths, type body lengths, function body lengths)
2. Improve Python test environment isolation to prevent .env file from affecting test results
3. Refactor Swift code for better organization and maintainability
4. Ensure all tests pass and lint checks pass

## Scope

**In scope:**
- Swift lint fixes in CameraSessionManager, CardDetectionEngine, AppModel, and related files
- Python test environment isolation in conftest.py and related tests
- Code refactoring to extract helper types and reduce file complexity
- Adding appropriate tests for refactored code

**Out of scope:**
- New feature development
- Changes to API contracts or response schemas
- iOS build verification (separate workflow)

## Verification

- `make lint` passes (both mypy and SwiftLint)
- `make api-test` passes (all 228 tests)
- No new lint suppressions without justification

## Context

Files or docs the agent should read before starting:

- `services/api/tests/conftest.py`
- `services/api/app/main.py`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraSessionManager.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Detection/CardDetectionEngine.swift`
- `.swiftlint.yml`

## Notes

- The work was done across 5 commits focusing on incremental improvements
- Test isolation changes were needed because the mock provider relies on specific environment configurations
