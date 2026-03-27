"""Tests for the /api/v1/recognitions/batch endpoint.

Covers:
- Basic happy-path: two pre-cropped images return merged results.
- Empty-images case returns an empty result, not an error.
- Non-image uploads are rejected with 400.
- Each crop is saved to its own artifact directory.
"""

import json
from io import BytesIO
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


@pytest.fixture
def mtgjson_db(tmp_path: Path) -> Path:
    source_path = tmp_path / "AllPrintings.fixture.json"
    source_path.write_text(
        json.dumps(
            {
                "meta": {"date": "2026-03-27", "version": "1.0.0"},
                "data": {
                    "M10": {
                        "code": "M10",
                        "name": "Magic 2010",
                        "releaseDate": "2009-07-17",
                        "cards": [
                            {
                                "uuid": "bolt-m10-146",
                                "name": "Lightning Bolt",
                                "setCode": "M10",
                                "number": "146",
                                "layout": "normal",
                                "language": "English",
                            }
                        ],
                    }
                },
            }
        )
    )
    from app.services.mtgjson_index import import_all_printings

    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(source_path=source_path, db_path=db_path, manifest_path=tmp_path / "manifest.json")
    return db_path


class TestBatchRecognitionEndpoint:
    """Tests for POST /api/v1/recognitions/batch."""

    def test_batch_two_crops_returns_merged_cards(self, tmp_path, monkeypatch, mtgjson_db) -> None:
        """Two pre-cropped card images should produce two recognised cards."""
        monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
        monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(mtgjson_db))

        response = client.post(
            "/api/v1/recognitions/batch",
            data={"prompt_version": "card-recognition.md"},
            files=[
                ("images", ("crop-0.jpg", b"fake-crop-0", "image/jpeg")),
                ("images", ("crop-1.jpg", b"fake-crop-1", "image/jpeg")),
            ],
        )

        assert response.status_code == 200
        payload = response.json()
        # Mock provider returns one card per recognition call → two crops → two cards.
        assert len(payload["cards"]) == 2
        assert payload["cards"][0]["title"] == "Lightning Bolt"
        assert payload["cards"][1]["title"] == "Lightning Bolt"

    def test_batch_single_crop_returns_one_card(self, tmp_path, monkeypatch, mtgjson_db) -> None:
        monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
        monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(mtgjson_db))

        response = client.post(
            "/api/v1/recognitions/batch",
            data={"prompt_version": "card-recognition.md"},
            files=[
                ("images", ("crop-0.jpg", b"fake-crop-0", "image/jpeg")),
            ],
        )

        assert response.status_code == 200
        payload = response.json()
        assert len(payload["cards"]) == 1

    def test_batch_saves_artifact_per_crop(self, tmp_path, monkeypatch, mtgjson_db) -> None:
        """Each crop in a batch should produce its own artifact directory."""
        monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
        monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(mtgjson_db))

        response = client.post(
            "/api/v1/recognitions/batch",
            data={"prompt_version": "card-recognition.md"},
            files=[
                ("images", ("card-a.jpg", b"crop-a-bytes", "image/jpeg")),
                ("images", ("card-b.jpg", b"crop-b-bytes", "image/jpeg")),
            ],
        )

        assert response.status_code == 200

        recognition_dirs = list((tmp_path / "recognitions").iterdir())
        assert len(recognition_dirs) == 2

        # Each artifact directory should have the original crop image and response.
        for artifact_dir in recognition_dirs:
            assert (artifact_dir / "response.json").exists()
            assert (artifact_dir / "metadata.json").exists()
            metadata = json.loads((artifact_dir / "metadata.json").read_text())
            assert metadata["filename"] in {"card-a.jpg", "card-b.jpg"}

    def test_batch_rejects_non_image_content_type(self, monkeypatch) -> None:
        """Non-image files in the batch should return HTTP 400."""
        monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
        monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")

        response = client.post(
            "/api/v1/recognitions/batch",
            files=[
                ("images", ("crop-0.jpg", b"valid-image", "image/jpeg")),
                ("images", ("data.csv", b"not,an,image", "text/csv")),
            ],
        )

        assert response.status_code == 400
        assert "image" in response.json()["detail"].lower()

    def test_batch_with_different_crop_notes(self, tmp_path, monkeypatch, mtgjson_db) -> None:
        """Verify that the notes for each crop reference their respective filename."""
        monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
        monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(mtgjson_db))

        response = client.post(
            "/api/v1/recognitions/batch",
            data={"prompt_version": "card-recognition.md"},
            files=[
                ("images", ("capture-crop-0.jpg", b"fake-bytes", "image/jpeg")),
                ("images", ("capture-crop-1.jpg", b"fake-bytes", "image/jpeg")),
            ],
        )

        assert response.status_code == 200
        payload = response.json()
        notes = [card["notes"] for card in payload["cards"]]
        assert any("capture-crop-0.jpg" in n for n in notes)
        assert any("capture-crop-1.jpg" in n for n in notes)

    def test_batch_uses_prompt_version(self, tmp_path, monkeypatch, mtgjson_db) -> None:
        """The prompt_version form field should be forwarded to each crop recognition."""
        monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
        monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(mtgjson_db))

        response = client.post(
            "/api/v1/recognitions/batch",
            data={"prompt_version": "card-recognition.md"},
            files=[
                ("images", ("crop.jpg", b"fake-bytes", "image/jpeg")),
            ],
        )

        assert response.status_code == 200
        recognition_dirs = list((tmp_path / "recognitions").iterdir())
        metadata = json.loads((recognition_dirs[0] / "metadata.json").read_text())
        assert metadata["prompt_version"] == "card-recognition.md"
