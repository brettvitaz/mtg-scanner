"""Tests for multi-card detection functionality."""

import json
from io import BytesIO
from pathlib import Path

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services.card_detector import CardDetector, CardRegion, DetectionResult

client = TestClient(app)


SAMPLES_DIR = Path(__file__).resolve().parents[3] / "samples" / "test"
ARTIFACTS_DIR = Path("/Users/brettvitaz/Development/mtg-scanner/services/.artifacts/recognitions")


class TestCardDetector:
    """Unit tests for the CardDetector."""

    def _create_test_image(self, width: int = 800, height: int = 600, color: tuple = (255, 255, 255)):
        """Create a test image as JPEG bytes."""
        import cv2

        image = np.full((height, width, 3), color, dtype=np.uint8)
        _, encoded = cv2.imencode(".jpg", image)
        return encoded.tobytes()

    def _create_image_with_card(self, card_bounds: tuple[int, int, int, int]):
        """Create an image with a simulated card region.

        Args:
            card_bounds: (x, y, width, height) of card
        """
        import cv2

        image = np.full((600, 800, 3), (128, 128, 128), dtype=np.uint8)
        x, y, w, h = card_bounds

        # Draw a card-like rectangle with border
        cv2.rectangle(image, (x, y), (x + w, y + h), (255, 255, 255), -1)
        cv2.rectangle(image, (x, y), (x + w, y + h), (0, 0, 0), 3)

        _, encoded = cv2.imencode(".jpg", image)
        return encoded.tobytes()

    def test_detector_initialization(self):
        """Test that CardDetector can be initialized with custom params."""
        detector = CardDetector(
            aspect_ratio_tolerance=0.3,
            min_card_area_percent=0.05,
        )
        assert detector._aspect_ratio_tolerance == 0.3
        assert detector._min_card_area_percent == 0.05

    def test_detector_default_initialization(self):
        """Test default detector initialization."""
        from app.services.card_detector import get_card_detector

        detector = get_card_detector()
        assert detector._aspect_ratio_tolerance == CardDetector.ASPECT_RATIO_TOLERANCE
        assert detector._min_card_area_percent == CardDetector.MIN_CARD_AREA_PERCENT

    def test_detect_empty_image(self):
        """Test detection on invalid image bytes."""
        detector = CardDetector()
        result = detector.detect(b"not-an-image")
        assert result.count == 0
        assert result.original_shape == (0, 0)

    def test_detect_single_card(self):
        """Test detection of a single card in an image."""
        detector = CardDetector()

        # Create image with one card (~MTG aspect ratio)
        # MTG card ratio: 2.5/3.5 = ~0.714
        card_width = 200
        card_height = int(card_width / CardDetector.TARGET_ASPECT_RATIO)
        image_bytes = self._create_image_with_card((100, 100, card_width, card_height))

        result = detector.detect(image_bytes)
        assert result.count >= 1
        assert result.original_shape[0] > 0
        assert result.original_shape[1] > 0

        # Check first region
        region = result.regions[0]
        assert region.width > 0
        assert region.height > 0
        assert region.confidence > 0

    def test_detect_multiple_cards(self):
        """Test detection of multiple cards in an image."""
        import cv2

        detector = CardDetector()

        # Create image with two cards side by side
        image = np.full((600, 800, 3), (128, 128, 128), dtype=np.uint8)

        card_width = 180
        card_height = int(card_width / CardDetector.TARGET_ASPECT_RATIO)

        # Card 1
        x1, y1 = 100, 100
        cv2.rectangle(image, (x1, y1), (x1 + card_width, y1 + card_height), (255, 255, 255), -1)
        cv2.rectangle(image, (x1, y1), (x1 + card_width, y1 + card_height), (0, 0, 0), 3)

        # Card 2
        x2, y2 = 350, 100
        cv2.rectangle(image, (x2, y2), (x2 + card_width, y2 + card_height), (255, 255, 255), -1)
        cv2.rectangle(image, (x2, y2), (x2 + card_width, y2 + card_height), (0, 0, 0), 3)

        _, encoded = cv2.imencode(".jpg", image)
        image_bytes = encoded.tobytes()

        result = detector.detect(image_bytes)

        # Should detect at least 2 cards (may detect more due to noise)
        assert result.count >= 2

    def test_crop_region(self):
        """Test cropping a detected region."""
        import cv2

        detector = CardDetector()

        # Create test image with a distinct region
        image = np.zeros((400, 400, 3), dtype=np.uint8)
        cv2.rectangle(image, (50, 50), (150, 200), (255, 0, 0), -1)  # Blue rectangle

        _, encoded = cv2.imencode(".jpg", image)
        image_bytes = encoded.tobytes()

        region = CardRegion(x=50, y=50, width=100, height=150, confidence=0.9)
        crop_bytes, content_type = detector.crop_region(image_bytes, region)

        assert isinstance(crop_bytes, bytes)
        assert len(crop_bytes) > 0
        assert content_type == "image/jpeg"

    def test_refine_cropped_card_trims_simple_spillover(self):
        """A local trim pass should snap inward from obvious dark card borders."""
        import cv2

        detector = CardDetector()
        image = np.full((220, 180, 3), 210, dtype=np.uint8)
        cv2.rectangle(image, (20, 15), (160, 205), (25, 25, 25), -1)
        cv2.rectangle(image, (26, 21), (154, 199), (235, 235, 235), -1)

        refined = detector._refine_cropped_card(image)
        refined_height, refined_width = refined.shape[:2]

        assert refined_width < image.shape[1] - 10
        assert refined_height < image.shape[0] - 10
        assert abs((refined_width / refined_height) - CardDetector.TARGET_ASPECT_RATIO) < 0.08

    def test_real_sample_image_detects_two_cards(self):
        """Regression test for the real two-card sample that previously returned one card."""
        detector = CardDetector()
        image_bytes = (SAMPLES_DIR / "IMG_1611.png").read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == 2
        assert all(region.corners is not None for region in result.regions)

    @pytest.mark.parametrize(
        ("filename", "expected_count"),
        [
            ("IMG_1619.png", 1),
            ("IMG_1620.png", 2),
            ("IMG_1621.png", 3),
            ("IMG_1622.png", 4),
            ("IMG_1623.png", 5),
            ("IMG_1624.png", 6),
            ("IMG_1625.png", 7),
            ("IMG_1626.png", 9),
            ("IMG_1627.png", 9),
        ],
    )
    def test_real_sample_ladder_detects_expected_cards(self, filename: str, expected_count: int):
        """Real sample ladder regressions should stay pinned to their expected card counts."""
        detector = CardDetector()
        image_bytes = (SAMPLES_DIR / filename).read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == expected_count

    def test_binder_page_detects_nine_cards(self):
        """Dense 3x3 binder pages should resolve to all nine cards."""
        detector = CardDetector()
        image_bytes = (SAMPLES_DIR / "binder_page_1.jpg").read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == 9
        assert len([region for region in result.regions if region.confidence >= 0.6]) == 9

    def test_real_two_card_artifact_stays_at_two_cards(self):
        """Dense-layout inference should not add a spurious container region to normal two-card shots."""
        detector = CardDetector()
        image_bytes = (ARTIFACTS_DIR / "20260326T042740-313a4c56" / "upload.jpg").read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == 2
        assert all(region.corners is not None for region in result.regions)

    def test_real_three_card_artifact_stays_at_three_cards(self):
        """Three-card table shots should not produce extra nested crops."""
        detector = CardDetector()
        image_bytes = (ARTIFACTS_DIR / "20260326T043745-01c5b1b9" / "upload.jpg").read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == 3
        assert sum(1 for region in result.regions if region.confidence >= 0.5) >= 2

    def test_duplicate_crop_bug_keeps_distinct_two_cards(self):
        """Overlapping candidates for the same physical card should collapse to one crop per card."""
        detector = CardDetector()
        image_bytes = (ARTIFACTS_DIR / "20260326T044827-23ae7d33" / "upload.jpg").read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == 2
        assert all(region.corners is not None for region in result.regions)
        assert max(detector._polygon_iou(result.regions[0], result.regions[1]), detector._polygon_iou(result.regions[1], result.regions[0])) < 0.05

    def test_binder_page_crop_refinement_trims_spillover_on_real_artifact(self):
        """The crop refinement pass should tighten top-row binder-page crops without changing card count."""
        import cv2

        detector = CardDetector()
        artifact_path = ARTIFACTS_DIR / "20260326T051835-8fe04381" / "upload.jpg"
        image_bytes = artifact_path.read_bytes()
        image_array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)

        result = detector.detect(image_bytes)
        assert result.count == 9

        eternal_witness = result.regions[0]
        liliana = result.regions[1]

        raw_eternal = detector._perspective_crop(image, eternal_witness)
        raw_liliana = detector._bounding_box_crop(image, liliana)

        refined_eternal = cv2.imdecode(np.frombuffer(detector.crop_region(image_bytes, eternal_witness)[0], dtype=np.uint8), cv2.IMREAD_COLOR)
        refined_liliana = cv2.imdecode(np.frombuffer(detector.crop_region(image_bytes, liliana)[0], dtype=np.uint8), cv2.IMREAD_COLOR)

        assert refined_eternal.shape[0] < raw_eternal.shape[0] - 100
        assert refined_eternal.shape[1] < raw_eternal.shape[1] - 100
        assert refined_liliana.shape[0] < raw_liliana.shape[0] - 150
        assert refined_liliana.shape[1] < raw_liliana.shape[1] - 80
        assert abs((refined_eternal.shape[1] / refined_eternal.shape[0]) - CardDetector.TARGET_ASPECT_RATIO) < 0.08
        assert abs((refined_liliana.shape[1] / refined_liliana.shape[0]) - CardDetector.TARGET_ASPECT_RATIO) < 0.08

    def test_iou_calculation(self):
        """Test IoU (Intersection over Union) calculation."""
        detector = CardDetector()

        r1 = CardRegion(x=0, y=0, width=100, height=100, confidence=1.0)
        r2 = CardRegion(x=50, y=50, width=100, height=100, confidence=1.0)
        r3 = CardRegion(x=200, y=200, width=100, height=100, confidence=1.0)

        # Overlapping regions
        iou = detector._iou(r1, r2)
        assert 0 < iou < 1

        # Non-overlapping regions
        iou = detector._iou(r1, r3)
        assert iou == 0.0

        # Same region
        iou = detector._iou(r1, r1)
        assert iou == 1.0


class TestMultiCardRecognitionAPI:
    """Integration tests for multi-card recognition via API."""

    def test_crop_regression_real_sample_counts(self):
        """Real regression samples should stay pinned to expected crop counts."""
        detector = CardDetector()

        cases = [
            (ARTIFACTS_DIR / "20260326T042740-313a4c56" / "upload.jpg", 2),
            (ARTIFACTS_DIR / "20260326T043745-01c5b1b9" / "upload.jpg", 3),
            (ARTIFACTS_DIR / "20260326T044827-23ae7d33" / "upload.jpg", 2),
            *[(SAMPLES_DIR / f"IMG_{index}.png", expected) for index, expected in zip(range(1619, 1628), [1, 2, 3, 4, 5, 6, 7, 9, 9], strict=True)],
            (SAMPLES_DIR / "binder_page_1.jpg", 9),
        ]

        for image_path, expected_count in cases:
            result = detector.detect(image_path.read_bytes())
            assert result.count == expected_count, f"{image_path} expected {expected_count} cards, got {result.count}"

    def test_recognition_saves_detection_metadata(self, tmp_path, monkeypatch):
        """Test that detection results are saved in metadata."""
        import cv2
        import numpy as np

        monkeypatch.delenv("MTG_SCANNER_RECOGNIZER_PROVIDER", raising=False)
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))

        # Create image with one card-like rectangle
        image = np.full((400, 600, 3), (128, 128, 128), dtype=np.uint8)
        cv2.rectangle(image, (100, 100), (250, 350), (255, 255, 255), -1)
        cv2.rectangle(image, (100, 100), (250, 350), (0, 0, 0), 3)

        _, encoded = cv2.imencode(".jpg", image)
        image_bytes = encoded.tobytes()

        response = client.post(
            "/api/v1/recognitions",
            data={"prompt_version": "card-recognition.md"},
            files={"image": ("multi-card.jpg", BytesIO(image_bytes), "image/jpeg")},
        )

        assert response.status_code == 200

        # Check saved artifacts
        recognition_dirs = list((tmp_path / "recognitions").iterdir())
        assert len(recognition_dirs) == 1

        artifact_dir = recognition_dirs[0]
        metadata = json.loads((artifact_dir / "metadata.json").read_text())

        # Should have detection info
        assert "detected_cards" in metadata
        assert metadata["detected_cards"] >= 1
        assert "original_shape" in metadata

    def test_recognition_saves_crops_when_multiple_detected(self, tmp_path, monkeypatch):
        """Test that individual card crops are saved when multiple cards detected."""
        import cv2
        import numpy as np

        monkeypatch.delenv("MTG_SCANNER_RECOGNIZER_PROVIDER", raising=False)
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))

        # Create image with two distinct cards
        image = np.full((600, 800, 3), (128, 128, 128), dtype=np.uint8)

        # Card 1 (left)
        cv2.rectangle(image, (50, 100), (200, 380), (255, 255, 255), -1)
        cv2.rectangle(image, (50, 100), (200, 380), (0, 0, 0), 3)

        # Card 2 (right)
        cv2.rectangle(image, (300, 100), (450, 380), (255, 255, 255), -1)
        cv2.rectangle(image, (300, 100), (450, 380), (0, 0, 0), 3)

        _, encoded = cv2.imencode(".jpg", image)
        image_bytes = encoded.tobytes()

        response = client.post(
            "/api/v1/recognitions",
            data={"prompt_version": "card-recognition.md"},
            files={"image": ("two-cards.jpg", BytesIO(image_bytes), "image/jpeg")},
        )

        assert response.status_code == 200

        # Check for crops directory
        recognition_dirs = list((tmp_path / "recognitions").iterdir())
        artifact_dir = recognition_dirs[0]
        crops_dir = artifact_dir / "crops"

        assert crops_dir.exists()
        crops = sorted(crops_dir.glob("*.jpg"))
        assert len(crops) >= 1  # At least one crop saved

        metadata = json.loads((artifact_dir / "metadata.json").read_text())
        assert "crop_files" in metadata
        assert len(metadata["crop_files"]) == len(crops)
        assert all("crop_path" in region for region in metadata["regions"])

    def test_backward_compatibility_single_card(self, tmp_path, monkeypatch):
        """Test that single-card images still work correctly."""
        monkeypatch.delenv("MTG_SCANNER_RECOGNIZER_PROVIDER", raising=False)
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))

        # Use simple fake image (no card-like features, so detection may fail gracefully)
        response = client.post(
            "/api/v1/recognitions",
            data={"prompt_version": "card-recognition.md"},
            files={"image": ("single-card.jpg", b"fake-image-bytes", "image/jpeg")},
        )

        assert response.status_code == 200
        payload = response.json()
        assert "cards" in payload
        assert len(payload["cards"]) >= 1

    def test_multi_card_detection_disabled(self, tmp_path, monkeypatch):
        """Test that multi-card detection can be disabled."""
        monkeypatch.delenv("MTG_SCANNER_RECOGNIZER_PROVIDER", raising=False)
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
        monkeypatch.setenv("MTG_SCANNER_ENABLE_MULTI_CARD", "false")

        response = client.post(
            "/api/v1/recognitions",
            data={"prompt_version": "card-recognition.md"},
            files={"image": ("test.jpg", b"fake-image-bytes", "image/jpeg")},
        )

        assert response.status_code == 200
