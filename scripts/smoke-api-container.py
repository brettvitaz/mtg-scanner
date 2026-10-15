#!/usr/bin/env python3
"""Verify the API image with mock recognition, with or without Compose mounts."""

import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import time

import cv2
import httpx
import numpy as np

from app.models.recognition import RecognitionResponse
from app.settings import get_settings
from app.services.artifact_store import get_artifacts_base_dir


def wait_for_health(client: httpx.Client, server: subprocess.Popen) -> None:
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if server.poll() is not None:
            raise RuntimeError("Uvicorn exited before becoming healthy")
        try:
            response = client.get("/health")
            response.raise_for_status()
            assert response.json() == {"status": "ok"}
            return
        except httpx.TransportError:
            time.sleep(0.1)
    raise RuntimeError("Uvicorn did not become healthy within 30 seconds")


def check_databases() -> None:
    settings = get_settings()
    for name, query in (
        (settings.mtg_scanner_mtgjson_db_path, "SELECT count(*) FROM cards"),
        (settings.mtg_scanner_ck_prices_db_path, "SELECT count(*) FROM ck_prices"),
    ):
        with sqlite3.connect(f"file:{name}?mode=ro", uri=True) as database:
            assert database.execute("PRAGMA integrity_check").fetchone() == ("ok",)
            assert database.execute(query).fetchone()[0] > 0
    assert json.loads(Path("services/api/data/pricing/model_prices.json").read_text())["models"]


def check_recognition(client: httpx.Client, require_validation: bool) -> None:
    directory = get_artifacts_base_dir() / "recognitions"
    before = set(directory.glob("*/metadata.json"))
    encoded, image = cv2.imencode(".png", np.full((400, 300, 3), 255, dtype=np.uint8))
    assert encoded
    response = client.post("/api/v1/recognitions", files={"image": ("docker-smoke.png", image.tobytes(), "image/png")})
    response.raise_for_status()
    result = RecognitionResponse.model_validate(response.json())
    assert result.cards and result.cards[0].title == "Lightning Bolt"
    created = set(directory.glob("*/metadata.json")) - before
    assert len(created) == 1
    metadata_path = created.pop()
    metadata = json.loads(metadata_path.read_text())
    assert metadata["provider"] == "mock"
    if require_validation:
        assert metadata["validation"]["available"] is True
    assert (metadata_path.parent / "upload.png").is_file()
    assert (metadata_path.parent / "response.json").is_file()
    print(f"Recognition and validation passed; artifacts: {metadata_path.parent}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--standalone", action="store_true", help="Test without seeded databases or Compose mounts")
    args = parser.parse_args()
    settings = get_settings()
    assert settings.mtg_scanner_llm_provider == "mock", "Smoke test requires mock provider"
    assert settings.mtg_scanner_enable_llm_correction is False
    assert settings.mtg_scanner_pricing_refresh_interval_hours == 0
    if not args.standalone:
        check_databases()
    server = subprocess.Popen([sys.executable, "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000"])
    try:
        with httpx.Client(base_url="http://127.0.0.1:8000", timeout=30) as client:
            wait_for_health(client, server)
            if not args.standalone:
                response = client.get("/api/v1/cards/printings", params={"name": "Lightning Bolt"})
                response.raise_for_status()
                assert response.json()["printings"]
            check_recognition(client, require_validation=not args.standalone)
            assert Path("services/api/logs/app.log").is_file()
        print("PASS: mock HTTP recognition, artifact writes, and application logging")
    finally:
        server.terminate()
        server.wait(timeout=10)


if __name__ == "__main__":
    main()
