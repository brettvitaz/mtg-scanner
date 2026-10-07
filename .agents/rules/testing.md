# Testing Rules

## Test quality
- Every behavior change needs a test that fails if that behavior breaks. For purely visual behavior, use a snapshot route (see `apps/ios/AGENTS.md`).
- Tests must exercise real code paths — no tests that only verify mocks or hardcoded values.
- A test must fail if the implementation is broken. Ask: "If I deleted the implementation body, would this test fail?"
- Do not write tests that test language features rather than your logic.
- Put logic that a test must reach in a model, view model, or service, not in a SwiftUI view body or view modifier. The view calls it; the test calls the same method.
- Check that the code under test can actually change the result. A test of "stopping does not clear X" proves nothing if the stop code has no access to X.
- When a test waits for async work, poll for the expected condition with a limit, then fail with a message (see `waitForCapture` in `AutoScanCaptureLifecycleTests.swift`). Do not wait a fixed time and hope the work finished.

## What to test
- Given specific inputs, verify specific outputs (value-based assertions).
- Edge cases: empty input, boundary values, nil/optional paths, zero-size inputs.
- Error conditions: invalid inputs should not crash; verify defined behavior.
- For detection/recognition: test with real sample images from `samples/test/` when possible.

## Python (pytest)
- Tests live in `services/api/tests/`. Run them with `make api-test` or `pytest services/api/tests/`.
- Use `FastAPI.TestClient` for endpoint tests.
- Use `monkeypatch` for environment variable overrides.
- Use `tmp_path` for isolated file system operations.
- Tests must not require network access or API credentials — use the mock provider.
- Schema validation: `test_schema_examples.py` validates examples with jsonschema `Draft202012Validator`.
- Fixtures go in `conftest.py` for shared state.

## Swift (XCTest)
- `final class <Feature>Tests: XCTestCase` naming pattern.
- Descriptive test method names: `test<Feature>_<scenario>_<expected>` or plain descriptive names.
- Use `XCTAssertEqual(_:_:accuracy:)` for floating-point comparisons.
- Use `XCTUnwrap` for required optional values; test files must pass SwiftLint.
- MARK sections to organize test groups within a file.

## Regression tests
- When fixing a bug in detection or cropping, add a regression test with the failing input.
- Sample images for regression live in `samples/test/`.
- Backend regression tests in `services/api/tests/test_multi_card.py` verify card counts on real images.
