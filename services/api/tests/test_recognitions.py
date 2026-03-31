import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.settings import get_settings
from app.services.recognizer import OpenAIRecognitionProvider, get_recognition_service

client = TestClient(app)


@pytest.fixture
def mtgjson_db(tmp_path: Path) -> Path:
    source_path = tmp_path / "AllPrintings.fixture.json"
    source_path.write_text(
        json.dumps(
            {
                "meta": {"date": "2026-03-26", "version": "1.0.0"},
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
                    },
                    "DFT": {
                        "code": "DFT",
                        "name": "Aetherdrift",
                        "releaseDate": "2026-02-14",
                        "cards": [
                            {
                                "uuid": "autarch-mammoth-dft-166",
                                "name": "Autarch Mammoth",
                                "setCode": "DFT",
                                "number": "166",
                                "layout": "normal",
                                "language": "English"
                            }
                        ]
                    },
                    "OTJ": {
                        "code": "OTJ",
                        "name": "Outlaws of Thunder Junction",
                        "releaseDate": "2024-04-19",
                        "cards": [
                            {
                                "uuid": "laughing-jasper-flint-otj-215",
                                "name": "Laughing Jasper Flint",
                                "setCode": "OTJ",
                                "number": "215",
                                "layout": "normal",
                                "language": "English"
                            }
                        ]
                    }
                },
            }
        )
    )
    from app.services.mtgjson_index import import_all_printings

    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(source_path=source_path, db_path=db_path, manifest_path=tmp_path / "manifest.json")
    return db_path


def test_recognition_upload_response(mtgjson_db: Path, monkeypatch) -> None:
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
    monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(mtgjson_db))
    response = client.post(
        "/api/v1/recognitions",
        data={"prompt_version": "card-recognition.md"},
        files={"image": ("lightning-bolt.jpg", b"fake-image-bytes", "image/jpeg")},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["cards"][0]["title"] == "Lightning Bolt"
    assert payload["cards"][0]["edition"] == "Magic 2010"
    assert payload["cards"][0]["collector_number"] == "146"
    assert "lightning-bolt.jpg" in payload["cards"][0]["notes"]


def test_recognition_rejects_non_image_upload() -> None:
    response = client.post(
        "/api/v1/recognitions",
        files={"image": ("notes.txt", b"not-an-image", "text/plain")},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Uploaded file must be an image."


def test_recognition_auto_corrects_impossible_title_and_set_combination(
    tmp_path, monkeypatch, mtgjson_db: Path
) -> None:
    """Autarch Mammoth only exists in DFT. When the LLM says OTJ, validation auto-corrects it."""
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "openai")
    monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
    monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(mtgjson_db))
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("MTG_SCANNER_OPENAI_MODEL", "gpt-4.1-mini")

    from app.models.recognition import RecognitionResponse
    from app.services import recognizer as recognizer_module

    def fake_recognize(self, image_bytes, metadata, prompt_text):  # type: ignore[no-untyped-def]
        del self, image_bytes, metadata, prompt_text
        return RecognitionResponse(
            cards=[
                {
                    "title": "Autarch Mammoth",
                    "edition": "Outlaws of Thunder Junction",
                    "collector_number": "166",
                    "foil": False,
                    "confidence": 0.92,
                    "notes": "Model guessed the set from weak packaging context.",
                }
            ]
        )

    monkeypatch.setattr(
        recognizer_module.OpenAIRecognitionProvider,
        "recognize",
        fake_recognize,
    )

    response = client.post(
        "/api/v1/recognitions",
        data={"prompt_version": "card-recognition.md"},
        files={"image": ("autarch-mammoth.jpg", b"fake-image-bytes", "image/jpeg")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["cards"][0]["title"] == "Autarch Mammoth"
    # Auto-corrected: OTJ is invalid for this card, DFT is the only valid set
    assert payload["cards"][0]["edition"] == "Aetherdrift"
    assert payload["cards"][0]["set_code"] == "DFT"
    assert payload["cards"][0]["collector_number"] == "166"
    assert "corrected_match" in payload["cards"][0]["notes"].lower()

    recognition_dirs = list((tmp_path / "recognitions").iterdir())
    saved_metadata = json.loads((recognition_dirs[0] / "metadata.json").read_text())
    assert saved_metadata["validation"]["cards"][0]["status"] == "corrected_match"
    assert saved_metadata["validation"]["cards"][0]["matched_uuid"] == "autarch-mammoth-dft-166"


def test_recognition_upload_saves_artifacts(tmp_path, monkeypatch, mtgjson_db: Path) -> None:
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
    monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
    monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(mtgjson_db))

    response = client.post(
        "/api/v1/recognitions",
        data={"prompt_version": "card-recognition.md"},
        files={"image": ("black-lotus.jpg", b"fake-image-bytes", "image/jpeg")},
    )

    assert response.status_code == 200

    recognition_dirs = list((tmp_path / "recognitions").iterdir())
    assert len(recognition_dirs) == 1

    artifact_dir = recognition_dirs[0]
    assert (artifact_dir / "upload.jpg").read_bytes() == b"fake-image-bytes"

    saved_response = json.loads((artifact_dir / "response.json").read_text())
    assert saved_response["cards"][0]["title"] == "Lightning Bolt"

    saved_metadata = json.loads((artifact_dir / "metadata.json").read_text())
    assert saved_metadata["filename"] == "black-lotus.jpg"
    assert saved_metadata["content_type"] == "image/jpeg"
    assert saved_metadata["prompt_version"] == "card-recognition.md"
    assert saved_metadata["provider"] == "mock"
    assert saved_metadata["model"] is None
    assert saved_metadata["validation"]["enabled"] is True
    assert saved_metadata["validation"]["available"] is True
    assert saved_metadata["validation"]["cards"][0]["status"] == "exact_match"


def test_recognition_can_use_openai_provider_without_live_access(
    tmp_path, monkeypatch
) -> None:
    monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("MTG_SCANNER_OPENAI_MODEL", "gpt-4.1-mini")
    monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")

    from app.models.recognition import RecognitionResponse
    from app.services import recognizer as recognizer_module

    def fake_recognize(self, image_bytes, metadata, prompt_text):  # type: ignore[no-untyped-def]
        assert self.model_name == "gpt-4.1-mini"
        assert metadata.provider == "openai"
        assert metadata.model == "gpt-4.1-mini"
        assert metadata.content_type == "image/jpeg"
        assert image_bytes == b"fake-image-bytes"
        assert "MTG Card Recognition Prompt" in prompt_text
        return RecognitionResponse(
            cards=[
                {
                    "title": "Black Lotus",
                    "edition": "Limited Edition Alpha",
                    "collector_number": None,
                    "foil": False,
                    "confidence": 0.98,
                    "notes": "Title art and frame match clearly.",
                }
            ]
        )

    monkeypatch.setattr(
        recognizer_module.OpenAIRecognitionProvider,
        "recognize",
        fake_recognize,
    )

    response = client.post(
        "/api/v1/recognitions",
        data={"prompt_version": "card-recognition.md"},
        files={"image": ("black-lotus.jpg", b"fake-image-bytes", "image/jpeg")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["cards"][0]["title"] == "Black Lotus"
    assert payload["cards"][0]["confidence"] == 0.98

    recognition_dirs = list((tmp_path / "recognitions").iterdir())
    assert len(recognition_dirs) == 1
    saved_metadata = json.loads((recognition_dirs[0] / "metadata.json").read_text())
    assert saved_metadata["provider"] == "openai"
    assert saved_metadata["model"] == "gpt-4.1-mini"


def test_openai_provider_requires_env_when_selected(monkeypatch) -> None:
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "openai")
    monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")
    monkeypatch.setenv("OPENAI_API_KEY", "")
    monkeypatch.setenv("MTG_SCANNER_OPENAI_MODEL", "")

    response = client.post(
        "/api/v1/recognitions",
        data={"prompt_version": "card-recognition.md"},
        files={"image": ("black-lotus.jpg", b"fake-image-bytes", "image/jpeg")},
    )

    assert response.status_code == 500
    assert "OPENAI_API_KEY must be set" in response.json()["detail"]


def test_openai_provider_timeout_defaults_to_thirty_seconds(monkeypatch) -> None:
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("MTG_SCANNER_OPENAI_MODEL", "gpt-4.1-mini")
    monkeypatch.setenv("MTG_SCANNER_ENABLE_MULTI_CARD", "false")
    monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")
    monkeypatch.delenv("MTG_SCANNER_OPENAI_TIMEOUT_SECONDS", raising=False)

    service = get_recognition_service()

    assert isinstance(service._provider, OpenAIRecognitionProvider)
    assert service._provider._timeout_seconds == 30.0


def test_openai_provider_timeout_can_be_configured(monkeypatch) -> None:
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("MTG_SCANNER_OPENAI_MODEL", "gpt-4.1-mini")
    monkeypatch.setenv("MTG_SCANNER_ENABLE_MULTI_CARD", "false")
    monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")
    monkeypatch.setenv("MTG_SCANNER_OPENAI_TIMEOUT_SECONDS", "12.5")

    service = get_recognition_service()

    assert isinstance(service._provider, OpenAIRecognitionProvider)
    assert service._provider._timeout_seconds == 12.5


def test_max_concurrent_recognitions_defaults_to_four(monkeypatch) -> None:
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
    monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")
    monkeypatch.delenv("MTG_SCANNER_MAX_CONCURRENT_RECOGNITIONS", raising=False)

    settings = get_settings()
    service = get_recognition_service()

    assert settings.mtg_scanner_max_concurrent_recognitions == 4
    assert service._max_concurrent_recognitions == 4


def test_max_concurrent_recognitions_uses_configured_value(monkeypatch) -> None:
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
    monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")
    monkeypatch.setenv("MTG_SCANNER_MAX_CONCURRENT_RECOGNITIONS", "7")

    settings = get_settings()
    service = get_recognition_service()

    assert settings.mtg_scanner_max_concurrent_recognitions == 7
    assert service._max_concurrent_recognitions == 7


def test_recognition_gracefully_skips_validation_when_db_missing(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
    monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
    monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(tmp_path / "missing.sqlite"))

    response = client.post(
        "/api/v1/recognitions",
        data={"prompt_version": "card-recognition.md"},
        files={"image": ("lightning-bolt.jpg", b"fake-image-bytes", "image/jpeg")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["cards"][0]["title"] == "Lightning Bolt"

    recognition_dirs = list((tmp_path / "recognitions").iterdir())
    saved_metadata = json.loads((recognition_dirs[0] / "metadata.json").read_text())
    assert saved_metadata["validation"]["available"] is False
    assert saved_metadata["validation"]["cards"][0]["status"] == "validation_unavailable"


def test_recognition_gracefully_skips_validation_when_db_corrupt(tmp_path, monkeypatch) -> None:
    corrupt_db = tmp_path / "corrupt.sqlite"
    corrupt_db.write_text("not a sqlite database")

    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock")
    monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
    monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(corrupt_db))

    response = client.post(
        "/api/v1/recognitions",
        data={"prompt_version": "card-recognition.md"},
        files={"image": ("lightning-bolt.jpg", b"fake-image-bytes", "image/jpeg")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["cards"][0]["title"] == "Lightning Bolt"

    recognition_dirs = list((tmp_path / "recognitions").iterdir())
    saved_metadata = json.loads((recognition_dirs[0] / "metadata.json").read_text())
    assert saved_metadata["validation"]["available"] is False
    assert saved_metadata["validation"]["cards"][0]["status"] == "validation_unavailable"
    assert "unreadable" in saved_metadata["validation"]["cards"][0]["reason"].lower()
