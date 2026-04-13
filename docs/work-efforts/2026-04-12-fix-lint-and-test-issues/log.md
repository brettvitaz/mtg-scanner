# Log: Fix lint and test issues

## Progress

### Step 1: Python test environment isolation

**Status:** done

Added `_isolate_settings_from_dotenv()` function to `conftest.py` that disables dotenv loading by setting `Settings.model_config["env_file"] = ()` and clearing relevant environment variables. Called at module import time before any test modules load.

Deviations from plan: none

---

### Step 2: Add test_settings_bootstrap.py validation test

**Status:** done

Created new test file `test_settings_bootstrap.py` that verifies dotenv is disabled before app import and validates settings isolation at module level.

Deviations from plan: none

---

### Step 3: Extract PhotoCaptureHandler to own file

**Status:** done

Moved `PhotoCaptureHandler` class from `CameraSessionManager.swift` to new file `PhotoCaptureHandler.swift`. Made the class `final` and `internal` (removed `private`).

Deviations from plan: none

---

### Step 4: Extract ScanYOLOSupport to own file

**Status:** done

Moved `ScanYOLOSupport` enum and related types (`ScanYOLOValidationState`, `ScanYOLORefreshDecision`, `ScanYOLOValidationResult`, `SendablePixelBuffer`, `SendableYOLODetector`) from `CardDetectionEngine.swift` to new file `ScanYOLOSupport.swift`.

Deviations from plan: none

---

### Step 5: Reorganize CameraSessionManager with MARK extensions

**Status:** done

Added MARK-based organization with extensions for Focus helpers, Torch, and Lifecycle. Extracted focus configuration methods to `private extension CameraSessionManager`.

Deviations from plan: none

---

### Step 6: Refactor CardDetectionEngine debug logging

**Status:** done

Extracted debug logging to `logScanFrame()` method inside `#if DEBUG` block. Removed inline debug code from `detectScanCards()`.

Deviations from plan: none

---

### Step 7: Fix AppModel line length violations

**Status:** done

Fixed long lines by introducing intermediate variables. Changed `"\(stem)-crop-\(i).\(payload.preferredFilenameExtension)"` to use `let ext = payload.preferredFilenameExtension`.

Deviations from plan: none

---

### Step 8: Extract NMS logic in RectangleFilter

**Status:** done

Extracted NMS loop to `applyNMS(to:)` helper method. Extracted containment suppression to `applyContainmentSuppression(to:)`.

Deviations from plan: none

---

### Step 9: Add RectangleFilterNMSTests.swift

**Status:** done

Created new test file with tests for the extracted NMS logic covering duplicate detection and confidence ordering.

Deviations from plan: none

---

### Step 10: Add ScanYOLOSupportValidationTests.swift

**Status:** done

Created new test file with tests for YOLO validation logic covering empty observations, fallback behavior, and acceptance/rejection scenarios.

Deviations from plan: none

---

### Step 11: Reorder imports in conftest.py

**Status:** done

Reordered imports in `conftest.py` for clarity (stdlib before third-party).

Deviations from plan: none

---

### Step 12: Verify all tests and lint

**Status:** done

Ran `make api-test` - all 228 tests passed. Ran `make api-lint` - mypy passed. Verified SwiftLint passed for all 98 files.

Deviations from plan: none
