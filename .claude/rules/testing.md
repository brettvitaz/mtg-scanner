---
paths:
  - "services/api/tests/**/*.py"
  - "apps/ios/MTGScannerTests/**/*.swift"
---

# Testing Rules

## Test quality
- Every public method or type should have at least one test.
- Tests must exercise real code paths — no tests that only verify mocks or hardcoded values.
- A test must fail if the implementation is broken. Ask: "If I deleted the implementation body, would this test fail?"
- Do not write tests that test language features rather than your logic.

## What to test
- Given specific inputs, verify specific outputs (value-based assertions).
- Edge cases: empty input, boundary values, nil/optional paths, zero-size inputs.
- Error conditions: invalid inputs should not crash; verify defined behavior.
- For detection/recognition: test with real sample images from `samples/test/` when possible.

## Python (pytest)
- Use `FastAPI.TestClient` for endpoint tests.
- Use `monkeypatch` for environment variable overrides.
- Use `tmp_path` for isolated file system operations.
- Tests must not require network access or API credentials — use the mock provider.
- Schema validation uses jsonschema `Draft202012Validator`.
- Fixtures go in `conftest.py` for shared state.

## Swift (XCTest)
- `final class <Feature>Tests: XCTestCase` naming pattern.
- Descriptive test method names: `test<Feature>_<scenario>_<expected>` or plain descriptive names.
- Use `XCTAssertEqual(_:_:accuracy:)` for floating-point comparisons.
- Force unwraps are acceptable in test code for brevity.
- MARK sections to organize test groups within a file.

## Regression tests
- When fixing a bug in detection or cropping, add a regression test with the failing input.
- Sample images for regression live in `samples/test/`.
- Backend regression tests in `services/api/tests/test_multi_card.py` verify card counts on real images.
