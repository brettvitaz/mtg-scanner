import base64
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from app.main import app


def feedback() -> dict[str, Any]:
    _, image = cv2.imencode(".jpg", np.zeros((840, 600, 3), dtype=np.uint8))
    return {
        "event_id": "a3a76d5a-cb6c-40ba-9613-89d32e85d68b",
        "created_at": "2026-10-15T12:00:00Z",
        "original_recognition": {"title": "Wrong", "confidence": 0.4},
        "previous_identification": {"title": "Wrong", "edition": "Unknown", "foil": False},
        "corrected_identification": {"title": "Island", "edition": "Test", "foil": True},
        "scan_jpeg": base64.b64encode(image.tobytes()).decode(),
    }


def configure(monkeypatch: MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))


def test_feedback_stores_image_and_original_previous_corrected_metadata(monkeypatch: MonkeyPatch, tmp_path: Path) -> None:
    configure(monkeypatch, tmp_path)
    payload = feedback()
    response = TestClient(app).post("/api/v1/recognition-feedback", json=payload)
    assert response.status_code == 200
    assert response.json() == {"event_id": payload["event_id"], "accepted": True, "duplicate": False}
    directory = tmp_path / "recognition-feedback" / payload["event_id"]
    assert (directory / "scan.jpg").read_bytes() == base64.b64decode(payload["scan_jpeg"])
    metadata = json.loads((directory / "metadata.json").read_text())
    for key in ["original_recognition", "previous_identification", "corrected_identification"]:
        assert metadata[key] == payload[key]
    assert "scan_jpeg" not in metadata


def test_duplicate_and_concurrent_retries_do_not_overwrite_evidence(monkeypatch: MonkeyPatch, tmp_path: Path) -> None:
    configure(monkeypatch, tmp_path)
    payload = feedback()
    with ThreadPoolExecutor(max_workers=4) as executor:
        responses = list(executor.map(
            lambda _: TestClient(app).post("/api/v1/recognition-feedback", json=payload), range(4)
        ))
    assert all(response.status_code == 200 for response in responses)
    assert sum(not response.json()["duplicate"] for response in responses) == 1
    payload["corrected_identification"]["title"] = "Changed retry"
    assert TestClient(app).post("/api/v1/recognition-feedback", json=payload).json()["duplicate"]
    directories = list((tmp_path / "recognition-feedback").iterdir())
    assert len(directories) == 1
    assert json.loads((directories[0] / "metadata.json").read_text())["corrected_identification"]["title"] == "Island"


def test_invalid_image_and_event_id_are_rejected(monkeypatch: MonkeyPatch, tmp_path: Path) -> None:
    configure(monkeypatch, tmp_path)
    for changes in [{"scan_jpeg": "not base64"}, {"scan_jpeg": "aGVsbG8="}, {"event_id": "../../escape"}]:
        payload = feedback() | changes
        assert TestClient(app).post("/api/v1/recognition-feedback", json=payload).status_code == 422
    assert not (tmp_path / "recognition-feedback").exists()


def test_storage_failure_is_not_acknowledged_and_can_retry(monkeypatch: MonkeyPatch, tmp_path: Path) -> None:
    configure(monkeypatch, tmp_path)
    root = tmp_path / "recognition-feedback"
    root.write_text("blocked directory")
    payload = feedback()
    response = TestClient(app).post("/api/v1/recognition-feedback", json=payload)
    assert response.status_code == 500
    root.unlink()
    response = TestClient(app).post("/api/v1/recognition-feedback", json=payload)
    assert response.status_code == 200
    assert response.json()["duplicate"] is False
