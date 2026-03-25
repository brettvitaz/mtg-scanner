import json

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_recognition_upload_response() -> None:
    response = client.post(
        "/api/v1/recognitions",
        data={"prompt_version": "card-recognition.md"},
        files={"image": ("lightning-bolt.jpg", b"fake-image-bytes", "image/jpeg")},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["cards"][0]["title"] == "Lightning Bolt"
    assert "lightning-bolt.jpg" in payload["cards"][0]["notes"]


def test_recognition_rejects_non_image_upload() -> None:
    response = client.post(
        "/api/v1/recognitions",
        files={"image": ("notes.txt", b"not-an-image", "text/plain")},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Uploaded file must be an image."


def test_recognition_upload_saves_artifacts(tmp_path, monkeypatch) -> None:
    monkeypatch.delenv("MTG_SCANNER_RECOGNIZER_PROVIDER", raising=False)
    monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))

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


def test_recognition_can_use_openai_provider_without_live_access(
    tmp_path, monkeypatch
) -> None:
    monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
    monkeypatch.setenv("MTG_SCANNER_RECOGNIZER_PROVIDER", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("MTG_SCANNER_OPENAI_MODEL", "gpt-4.1-mini")

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
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("MTG_SCANNER_OPENAI_MODEL", raising=False)

    response = client.post(
        "/api/v1/recognitions",
        data={"prompt_version": "card-recognition.md"},
        files={"image": ("black-lotus.jpg", b"fake-image-bytes", "image/jpeg")},
    )

    assert response.status_code == 500
    assert "OPENAI_API_KEY must be set" in response.json()["detail"]
