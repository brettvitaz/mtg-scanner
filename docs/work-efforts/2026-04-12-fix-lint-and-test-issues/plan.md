# Plan: Fix lint and test issues

**Planned by:** big-pickle
**Date:** 2026-04-12

## Approach

Address SwiftLint violations by extracting long methods into smaller, focused helpers and reorganizing code with MARK comments. Fix Python test isolation by disabling dotenv loading at module import time in conftest.py. Refactor Swift code to extract nested types and helper functions into separate files for improved maintainability.

## Implementation Steps

1. **Python test isolation**: Modify `conftest.py` to call `_isolate_settings_from_dotenv()` at module load time, clearing Settings.model_config["env_file"] and relevant environment variables before any test imports

2. **Python validation test**: Add `test_settings_bootstrap.py` to verify that dotenv is disabled before app import and settings are properly isolated

3. **Swift PhotoCaptureHandler extraction**: Move `PhotoCaptureHandler` class from `CameraSessionManager.swift` to its own file for better organization

4. **Swift ScanYOLOSupport extraction**: Move `ScanYOLOSupport` enum and related types from `CardDetectionEngine.swift` to a new file

5. **Swift code organization**: Add MARK comments and reorganize `CameraSessionManager.swift` with extension-based grouping (Focus helpers, Torch, Lifecycle)

6. **Swift lint fixes**: Extract debug logging in `CardDetectionEngine` to dedicated methods, fix line length violations in `AppModel.swift`

7. **Swift test additions**: Add `RectangleFilterNMSTests.swift` for NMS logic, `ScanYOLOSupportValidationTests.swift` for YOLO validation

## Files to Modify

| File | Change |
|------|--------|
| `services/api/tests/conftest.py` | Add `_isolate_settings_from_dotenv()` function and call at module level |
| `services/api/tests/test_settings_bootstrap.py` | New file - validate dotenv isolation |
| `apps/ios/.../Camera/PhotoCaptureHandler.swift` | New file - extracted from CameraSessionManager |
| `apps/ios/.../Detection/ScanYOLOSupport.swift` | New file - extracted from CardDetectionEngine |
| `apps/ios/.../Camera/CameraSessionManager.swift` | Remove extracted class, add MARK extensions |
| `apps/ios/.../Detection/CardDetectionEngine.swift` | Remove extracted enum/types, refactor debug logging |
| `apps/ios/.../App/AppModel.swift` | Fix line length violations with intermediate variables |
| `apps/ios/.../Detection/RectangleFilter.swift` | Extract NMS logic to `applyNMS()` helper |
| `apps/ios/.../Tests/RectangleFilterNMSTests.swift` | New file - test NMS logic |
| `apps/ios/.../Tests/ScanYOLOSupportValidationTests.swift` | New file - test YOLO validation |

## Risks and Open Questions

- None identified - this is a well-scoped maintenance task

## Verification Plan

- Run `make api-test` to verify all 228 tests pass
- Run `make api-lint` to verify mypy passes
- Run `make ios-lint` to verify SwiftLint passes
- Verify no new lint suppressions were added
