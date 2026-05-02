"""Tests for multi-card detection functionality."""

import json
import threading
import time
from io import BytesIO

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models.recognition import RecognitionResponse, RecognitionResult, TokenUsage
from app.services.card_detector import CardDetector, CardRegion, DetectionResult
from conftest import ARTIFACTS_DIR, SAMPLES_DIR, requires_sample_images

client = TestClient(app)


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

    def test_refine_cropped_card_preserves_dark_outer_border(self):
        """The trim pass should keep the full border when a card has a dark frame and dark art near the edge."""
        import cv2

        detector = CardDetector()
        image = np.full((250, 190, 3), 208, dtype=np.uint8)
        cv2.rectangle(image, (14, 14), (176, 236), (18, 18, 18), -1)
        cv2.rectangle(image, (22, 22), (168, 228), (232, 232, 232), -1)
        cv2.rectangle(image, (26, 26), (164, 82), (32, 32, 32), -1)
        cv2.rectangle(image, (30, 90), (160, 224), (245, 245, 245), -1)

        refined = detector._refine_cropped_card(image)
        refined_gray = cv2.cvtColor(refined, cv2.COLOR_BGR2GRAY)

        assert refined.shape[1] >= 160
        assert refined.shape[0] >= 220
        assert refined_gray[:, :16].min() < 40
        assert refined_gray[:, -16:].min() < 40
        assert refined_gray[:16, :].min() < 40
        assert refined_gray[-16:, :].min() < 40
        assert abs((refined.shape[1] / refined.shape[0]) - CardDetector.TARGET_ASPECT_RATIO) < 0.08

    @requires_sample_images
    def test_real_sample_image_detects_two_cards(self):
        """Regression test for the real two-card sample that previously returned one card."""
        detector = CardDetector()
        image_bytes = (SAMPLES_DIR / "IMG_1611.png").read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == 2
        assert all(region.corners is not None for region in result.regions)

    @requires_sample_images
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
            ("hand_held_card.jpg", 1),
            ("bad_crop2.jpg", 1),
        ],
    )
    def test_real_sample_ladder_detects_expected_cards(self, filename: str, expected_count: int):
        """Real sample ladder regressions should stay pinned to their expected card counts."""
        detector = CardDetector()
        image_bytes = (SAMPLES_DIR / filename).read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == expected_count

    @requires_sample_images
    def test_binder_page_detects_nine_cards(self):
        """Dense 3x3 binder pages should resolve to all nine cards."""
        detector = CardDetector()
        image_bytes = (SAMPLES_DIR / "binder_page_1.jpg").read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == 9
        assert len([region for region in result.regions if region.confidence >= 0.6]) == 9

    @requires_sample_images
    def test_real_two_card_artifact_stays_at_two_cards(self):
        """Dense-layout inference should not add a spurious container region to normal two-card shots."""
        detector = CardDetector()
        image_bytes = (ARTIFACTS_DIR / "two_card_table.jpg").read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == 2
        assert all(region.corners is not None for region in result.regions)

    @requires_sample_images
    def test_real_three_card_artifact_stays_at_three_cards(self):
        """Three-card table shots should not produce extra nested crops."""
        detector = CardDetector()
        image_bytes = (ARTIFACTS_DIR / "three_card_table.jpg").read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == 3
        assert sum(1 for region in result.regions if region.confidence >= 0.5) >= 2

    @requires_sample_images
    def test_duplicate_crop_bug_keeps_distinct_two_cards(self):
        """Overlapping candidates for the same physical card should collapse to one crop per card."""
        detector = CardDetector()
        image_bytes = (ARTIFACTS_DIR / "duplicate_crop_two_card.jpg").read_bytes()

        result = detector.detect(image_bytes)

        assert result.count == 2
        assert all(region.corners is not None for region in result.regions)
        assert max(detector._polygon_iou(result.regions[0], result.regions[1]), detector._polygon_iou(result.regions[1], result.regions[0])) < 0.05

    @requires_sample_images
    def test_binder_page_crop_refinement_trims_spillover_on_real_artifact(self):
        """The crop refinement pass should tighten top-row binder-page crops without changing card count."""
        import cv2

        detector = CardDetector()
        artifact_path = ARTIFACTS_DIR / "binder_page_spillover.jpg"
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

        assert refined_eternal.shape[0] < raw_eternal.shape[0] - 35
        assert refined_eternal.shape[1] < raw_eternal.shape[1] - 30
        assert refined_eternal.shape[0] > raw_eternal.shape[0] * 0.85
        assert refined_liliana.shape[0] >= raw_liliana.shape[0] * 0.95
        assert refined_liliana.shape[1] >= raw_liliana.shape[1] * 0.95
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

    @requires_sample_images
    def test_crop_regression_real_sample_counts(self):
        """Real regression samples should stay pinned to expected crop counts."""
        detector = CardDetector()

        cases = [
            (ARTIFACTS_DIR / "two_card_table.jpg", 2),
            (ARTIFACTS_DIR / "three_card_table.jpg", 3),
            (ARTIFACTS_DIR / "duplicate_crop_two_card.jpg", 2),
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

        monkeypatch.setenv("MTG_SCANNER_LLM_PROVIDER", "mock")
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

        monkeypatch.setenv("MTG_SCANNER_LLM_PROVIDER", "mock")
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
        monkeypatch.setenv("MTG_SCANNER_LLM_PROVIDER", "mock")
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
        monkeypatch.setenv("MTG_SCANNER_LLM_PROVIDER", "mock")
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
        monkeypatch.setenv("MTG_SCANNER_ENABLE_MULTI_CARD", "false")

        response = client.post(
            "/api/v1/recognitions",
            data={"prompt_version": "card-recognition.md"},
            files={"image": ("test.jpg", b"fake-image-bytes", "image/jpeg")},
        )

        assert response.status_code == 200

    def test_multi_card_recognition_validates_each_card_independently(self, tmp_path, monkeypatch):
        mtgjson_source = tmp_path / "AllPrintings.fixture.json"
        mtgjson_source.write_text(
            json.dumps(
                {
                    "meta": {"date": "2026-03-26", "version": "1.0.0"},
                    "data": {
                        "M10": {
                            "code": "M10",
                            "name": "Magic 2010",
                            "releaseDate": "2009-07-17",
                            "cards": [
                                {"uuid": "bolt-m10-146", "name": "Lightning Bolt", "setCode": "M10", "number": "146", "layout": "normal", "language": "English"},
                                {"uuid": "forest-m10-247", "name": "Forest", "setCode": "M10", "number": "247", "layout": "normal", "language": "English"}
                            ],
                        }
                    },
                }
            )
        )
        from app.services.mtgjson_index import import_all_printings
        from app.services import recognizer as recognizer_module

        db_path = tmp_path / "mtgjson.sqlite"
        import_all_printings(source_path=mtgjson_source, db_path=db_path, manifest_path=tmp_path / "manifest.json")

        monkeypatch.setenv("MTG_SCANNER_LLM_PROVIDER", "mock")
        monkeypatch.setenv("MTG_SCANNER_ARTIFACTS_DIR", str(tmp_path))
        monkeypatch.setenv("MTG_SCANNER_MTGJSON_DB_PATH", str(db_path))
        monkeypatch.setenv("MTG_SCANNER_ENABLE_MULTI_CARD", "true")

        def fake_detect(self, image_bytes):  # type: ignore[no-untyped-def]
            del image_bytes
            return DetectionResult(
                regions=[
                    CardRegion(x=0, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=20, y=20, width=10, height=10, confidence=0.9),
                ],
                original_shape=(100, 100),
            )

        def fake_crop_region(self, image_bytes, region):  # type: ignore[no-untyped-def]
            del image_bytes, region
            return (b"crop-bytes", "image/jpeg")

        def fake_recognize(self, image_bytes, metadata, prompt_text):  # type: ignore[no-untyped-def]
            del image_bytes, prompt_text
            usage = TokenUsage(input_tokens=100, output_tokens=50, total_tokens=150)
            if metadata.filename.endswith("crop-0.jpg"):
                return RecognitionResult(response=RecognitionResponse(cards=[{"title": "Lightning Bolt", "edition": "M10", "collector_number": "146", "foil": False, "confidence": 0.9, "notes": "first crop"}]), usage=usage)
            return RecognitionResult(response=RecognitionResponse(cards=[{"title": "Totally Fake Card", "edition": "M10", "collector_number": "999", "foil": False, "confidence": 0.8, "notes": "second crop"}]), usage=usage)

        monkeypatch.setattr(CardDetector, "detect", fake_detect)
        monkeypatch.setattr(CardDetector, "crop_region", fake_crop_region)
        monkeypatch.setattr(recognizer_module.MockRecognitionProvider, "recognize", fake_recognize)

        response = client.post(
            "/api/v1/recognitions",
            data={"prompt_version": "card-recognition.md"},
            files={"image": ("test.jpg", b"fake-image-bytes", "image/jpeg")},
        )

        assert response.status_code == 200
        payload = response.json()
        assert [card["title"] for card in payload["cards"]] == ["Lightning Bolt", "Totally Fake Card"]
        assert payload["cards"][0]["edition"] == "Magic 2010"
        assert payload["cards"][1]["confidence"] == 0.55

    def test_multi_card_recognition_preserves_stable_ordering(self, monkeypatch):
        from app.models.recognition import RecognitionUploadMetadata
        from app.services import recognizer as recognizer_module

        monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")

        service = recognizer_module.RecognitionService(
            recognizer_module.MockRecognitionProvider(),
            card_detector=CardDetector(),
            validator=None,
            max_concurrent_recognitions=3,
        )

        def fake_detect(self, image_bytes):  # type: ignore[no-untyped-def]
            del self, image_bytes
            return DetectionResult(
                regions=[
                    CardRegion(x=0, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=20, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=40, y=0, width=10, height=10, confidence=0.9),
                ],
                original_shape=(100, 100),
            )

        def fake_crop_region(self, image_bytes, region):  # type: ignore[no-untyped-def]
            del self, region
            return (image_bytes, "image/jpeg")

        delays = {
            "upload.jpg-crop-0.jpg": 0.05,
            "upload.jpg-crop-1.jpg": 0.01,
            "upload.jpg-crop-2.jpg": 0.02,
        }

        def fake_recognize(self, image_bytes, metadata, prompt_text):  # type: ignore[no-untyped-def]
            del self, image_bytes, prompt_text
            time.sleep(delays[metadata.filename])
            crop_index = int(metadata.filename.split("-crop-")[1].split(".")[0])
            return RecognitionResult(
                response=RecognitionResponse(
                    cards=[
                        {
                            "title": f"Card {crop_index}",
                            "edition": "Test Set",
                            "collector_number": str(crop_index),
                            "foil": False,
                            "confidence": 0.9,
                            "notes": metadata.filename,
                        }
                    ]
                ),
                usage=TokenUsage(input_tokens=100, output_tokens=50, total_tokens=150),
            )

        monkeypatch.setattr(CardDetector, "detect", fake_detect)
        monkeypatch.setattr(CardDetector, "crop_region", fake_crop_region)
        monkeypatch.setattr(recognizer_module.MockRecognitionProvider, "recognize", fake_recognize)

        result = service.recognize(
            image_bytes=b"fake-image-bytes",
            metadata=RecognitionUploadMetadata(
                filename="upload.jpg",
                content_type="image/jpeg",
                prompt_version="card-recognition.md",
            ),
        )

        assert result.detection_result is not None
        assert result.validation_result is None
        assert [card.title for card in result.response.cards] == ["Card 0", "Card 1", "Card 2"]

    def test_multi_card_recognition_enforces_bounded_concurrency(self, monkeypatch):
        from app.models.recognition import RecognitionUploadMetadata
        from app.services import recognizer as recognizer_module

        monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")

        service = recognizer_module.RecognitionService(
            recognizer_module.MockRecognitionProvider(),
            card_detector=CardDetector(),
            validator=None,
            max_concurrent_recognitions=2,
        )

        def fake_detect(self, image_bytes):  # type: ignore[no-untyped-def]
            del self, image_bytes
            return DetectionResult(
                regions=[
                    CardRegion(x=0, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=20, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=40, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=60, y=0, width=10, height=10, confidence=0.9),
                ],
                original_shape=(100, 100),
            )

        def fake_crop_region(self, image_bytes, region):  # type: ignore[no-untyped-def]
            del self, region
            return (image_bytes, "image/jpeg")

        counters = {"current": 0, "max": 0}
        lock = threading.Lock()

        def fake_recognize(self, image_bytes, metadata, prompt_text):  # type: ignore[no-untyped-def]
            del self, image_bytes, metadata, prompt_text
            with lock:
                counters["current"] += 1
                counters["max"] = max(counters["max"], counters["current"])
            try:
                time.sleep(0.03)
                return RecognitionResult(
                    response=RecognitionResponse(
                        cards=[
                            {
                                "title": "Bounded Card",
                                "edition": "Test Set",
                                "collector_number": None,
                                "foil": False,
                                "confidence": 0.9,
                                "notes": "bounded",
                            }
                        ]
                    ),
                    usage=TokenUsage(input_tokens=100, output_tokens=50, total_tokens=150),
                )
            finally:
                with lock:
                    counters["current"] -= 1

        monkeypatch.setattr(CardDetector, "detect", fake_detect)
        monkeypatch.setattr(CardDetector, "crop_region", fake_crop_region)
        monkeypatch.setattr(recognizer_module.MockRecognitionProvider, "recognize", fake_recognize)

        result = service.recognize(
            image_bytes=b"fake-image-bytes",
            metadata=RecognitionUploadMetadata(
                filename="upload.jpg",
                content_type="image/jpeg",
                prompt_version="card-recognition.md",
            ),
        )

        assert len(result.response.cards) == 4
        assert counters["max"] == 2

    def test_multi_card_recognition_cancels_pending_work_on_first_exception(self, monkeypatch):
        from app.models.recognition import RecognitionUploadMetadata
        from app.services import recognizer as recognizer_module

        monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")

        service = recognizer_module.RecognitionService(
            recognizer_module.MockRecognitionProvider(),
            card_detector=CardDetector(),
            validator=None,
            max_concurrent_recognitions=2,
        )

        def fake_detect(self, image_bytes):  # type: ignore[no-untyped-def]
            del self, image_bytes
            return DetectionResult(
                regions=[
                    CardRegion(x=0, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=20, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=40, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=60, y=0, width=10, height=10, confidence=0.9),
                ],
                original_shape=(100, 100),
            )

        def fake_crop_region(self, image_bytes, region):  # type: ignore[no-untyped-def]
            del self, region
            return (image_bytes, "image/jpeg")

        started: list[str] = []
        queued_started = threading.Event()
        release_running = threading.Event()
        returned = threading.Event()
        failure: list[Exception] = []
        lock = threading.Lock()

        def fake_recognize(self, image_bytes, metadata, prompt_text):  # type: ignore[no-untyped-def]
            del self, image_bytes, prompt_text
            with lock:
                started.append(metadata.filename)
            if metadata.filename.endswith("crop-0.jpg"):
                raise RuntimeError("boom")
            if metadata.filename.endswith("crop-1.jpg"):
                release_running.wait(timeout=1.0)
            else:
                queued_started.set()
            return RecognitionResult(
                response=RecognitionResponse(
                    cards=[
                        {
                            "title": metadata.filename,
                            "edition": "Test Set",
                            "collector_number": None,
                            "foil": False,
                            "confidence": 0.9,
                            "notes": "ok",
                        }
                    ]
                ),
                usage=TokenUsage(input_tokens=100, output_tokens=50, total_tokens=150),
            )

        def run_recognition() -> None:
            try:
                service.recognize(
                    image_bytes=b"fake-image-bytes",
                    metadata=RecognitionUploadMetadata(
                        filename="upload.jpg",
                        content_type="image/jpeg",
                        prompt_version="card-recognition.md",
                    ),
                )
            except Exception as exc:  # noqa: BLE001
                failure.append(exc)
            finally:
                returned.set()

        monkeypatch.setattr(CardDetector, "detect", fake_detect)
        monkeypatch.setattr(CardDetector, "crop_region", fake_crop_region)
        monkeypatch.setattr(recognizer_module.MockRecognitionProvider, "recognize", fake_recognize)

        worker = threading.Thread(target=run_recognition)
        worker.start()

        try:
            assert returned.wait(timeout=0.5)
            assert len(failure) == 1
            assert str(failure[0]) == "boom"
            assert not queued_started.is_set()
            assert "upload.jpg-crop-0.jpg" in started
            assert set(started).issubset(
                {"upload.jpg-crop-0.jpg", "upload.jpg-crop-1.jpg"}
            )
        finally:
            release_running.set()
            worker.join(timeout=1.0)
            assert not worker.is_alive()

    def test_multi_card_recognition_prepares_all_crops_before_recognition(self, monkeypatch):
        from app.models.recognition import RecognitionUploadMetadata
        from app.services import recognizer as recognizer_module

        monkeypatch.setenv("MTG_SCANNER_ENABLE_MTG_VALIDATION", "false")

        service = recognizer_module.RecognitionService(
            recognizer_module.MockRecognitionProvider(),
            card_detector=CardDetector(),
            validator=None,
            max_concurrent_recognitions=2,
        )

        crop_events: list[str] = []
        recognize_events: list[str] = []

        def fake_detect(self, image_bytes):  # type: ignore[no-untyped-def]
            del self, image_bytes
            return DetectionResult(
                regions=[
                    CardRegion(x=0, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=20, y=0, width=10, height=10, confidence=0.9),
                    CardRegion(x=40, y=0, width=10, height=10, confidence=0.9),
                ],
                original_shape=(100, 100),
            )

        def fake_crop_region(self, image_bytes, region):  # type: ignore[no-untyped-def]
            del self, image_bytes
            crop_events.append(f"crop-{region.x}")
            return (f"crop-{region.x}".encode(), "image/jpeg")

        def fake_recognize(self, image_bytes, metadata, prompt_text):  # type: ignore[no-untyped-def]
            del self, prompt_text
            recognize_events.append(metadata.filename)
            assert len(crop_events) == 3
            return RecognitionResult(
                response=RecognitionResponse(
                    cards=[
                        {
                            "title": image_bytes.decode(),
                            "edition": "Test Set",
                            "collector_number": None,
                            "foil": False,
                            "confidence": 0.9,
                            "notes": metadata.filename,
                        }
                    ]
                ),
                usage=TokenUsage(input_tokens=100, output_tokens=50, total_tokens=150),
            )

        monkeypatch.setattr(CardDetector, "detect", fake_detect)
        monkeypatch.setattr(CardDetector, "crop_region", fake_crop_region)
        monkeypatch.setattr(recognizer_module.MockRecognitionProvider, "recognize", fake_recognize)

        result = service.recognize(
            image_bytes=b"fake-image-bytes",
            metadata=RecognitionUploadMetadata(
                filename="upload.jpg",
                content_type="image/jpeg",
                prompt_version="card-recognition.md",
            ),
        )

        assert crop_events == ["crop-0", "crop-20", "crop-40"]
        assert sorted(recognize_events) == [
            "upload.jpg-crop-0.jpg",
            "upload.jpg-crop-1.jpg",
            "upload.jpg-crop-2.jpg",
        ]
        assert [card.title for card in result.response.cards] == ["crop-0", "crop-20", "crop-40"]
