import json
from pathlib import Path

from jsonschema import Draft202012Validator

REPO_ROOT = Path(__file__).resolve().parents[3]
SCHEMAS_DIR = REPO_ROOT / "packages" / "schemas"
EXAMPLES_DIR = SCHEMAS_DIR / "examples" / "v1"


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text())


def test_recognition_upload_metadata_example_matches_schema() -> None:
    schema = _load_json(SCHEMAS_DIR / "v1" / "recognition-request.schema.json")
    example = _load_json(EXAMPLES_DIR / "recognition-request.sample.json")
    Draft202012Validator(schema).validate(example)


def test_recognition_response_example_matches_schema() -> None:
    schema = _load_json(SCHEMAS_DIR / "v1" / "recognition-response.schema.json")
    example = _load_json(EXAMPLES_DIR / "recognition-response.sample.json")
    Draft202012Validator(schema).validate(example)
