import base64
import json
from pathlib import Path

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from app.main import app
from app.models.recognition import RecognitionResponse, RecognitionResult, RecognitionUploadMetadata
from app.services.card_detector import CardDetector
from app.services.recognizer import MockRecognitionProvider, RecognitionService
from conftest import SAMPLES_DIR


def test_single_endpoint_returns_detected_crop_without_changing_recognition_input(
    monkeypatch: MonkeyPatch, tmp_path: Path,
) -> None:
    image = (SAMPLES_DIR / "hand_held_card.jpg").read_bytes()
    detector = CardDetector()
    detection = detector.detect(image)
    assert detection.count == 1
    crop, _ = detector.crop_region(image, detection.regions[0])
    recognize = MockRecognitionProvider.recognize

    def recognize_full_image(
        self: MockRecognitionProvider, image_bytes: bytes,
        metadata: RecognitionUploadMetadata, prompt_text: str,
    ) -> RecognitionResult:
        assert image_bytes == image
        return recognize(self, image_bytes, metadata, prompt_text)

    monkeypatch.setattr(MockRecognitionProvider, "recognize", recognize_full_image)
    service = RecognitionService(MockRecognitionProvider(), detector, enable_corner_crop=False)
    monkeypatch.setattr("app.api.routes.recognitions.get_recognition_service", lambda: service)
    monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
    response = TestClient(app).post(
        "/api/v1/recognitions", files={"image": ("hand_held_card.jpg", image, "image/jpeg")},
    )
    assert response.status_code == 200
    cards = response.json()["cards"]
    assert len(cards) == 1
    crop_data = cards[0]["crop_image_data"]
    assert isinstance(crop_data, str), "A usable single detected card must include its crop"
    returned = cv2.imdecode(np.frombuffer(base64.b64decode(crop_data), np.uint8), cv2.IMREAD_COLOR)
    expected = cv2.imdecode(np.frombuffer(crop, np.uint8), cv2.IMREAD_COLOR)
    assert returned is not None
    assert returned.shape == expected.shape
    assert np.abs(returned.astype(float) - expected.astype(float)).mean() < 10
    # The iOS persistence regression consumes this real single-endpoint response.
    fixture = SAMPLES_DIR.parents[1] / "apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CropEvaluationFixtures/hand-held-single-response.json"
    fixture_card = json.loads(fixture.read_text())["cards"][0]
    fixture_image = cv2.imdecode(np.frombuffer(base64.b64decode(fixture_card.pop("crop_image_data")), np.uint8), cv2.IMREAD_COLOR)
    assert fixture_image.shape == returned.shape
    assert np.abs(fixture_image.astype(float) - returned.astype(float)).mean() < 1
    assert fixture_card == {key: value for key, value in cards[0].items() if key != "crop_image_data"}
    saved = next(tmp_path.glob("recognitions/*/response.json"))
    assert json.loads(saved.read_text())["cards"][0]["crop_image_data"] == cards[0]["crop_image_data"]


@pytest.mark.parametrize("card_count", [0, 2])
def test_single_region_does_not_assign_evidence_to_ambiguous_results(card_count: int) -> None:
    class AmbiguousProvider(MockRecognitionProvider):
        def recognize(
            self, image_bytes: bytes, metadata: RecognitionUploadMetadata, prompt_text: str,
        ) -> RecognitionResult:
            result = super().recognize(image_bytes, metadata, prompt_text)
            return RecognitionResult(response=RecognitionResponse(cards=result.response.cards * card_count))

    result = RecognitionService(AmbiguousProvider(), CardDetector(), enable_corner_crop=False).recognize(
        image_bytes=(SAMPLES_DIR / "hand_held_card.jpg").read_bytes(),
        metadata=RecognitionUploadMetadata(filename="hand_held_card.jpg", content_type="image/jpeg"),
    )
    assert result.detection_result is not None
    assert result.detection_result.count == 1
    assert len(result.response.cards) == card_count
    assert all(card.crop_image_data is None for card in result.response.cards)
