"""Tests for RecognitionService behaviour."""
from unittest.mock import MagicMock, patch

import pytest

from app.models.recognition import RecognitionUploadMetadata
from app.services.recognizer import RecognitionService


@pytest.fixture
def mock_provider():
    """A minimal mock recognition provider."""
    from app.services.recognizer import MockRecognitionProvider

    return MockRecognitionProvider()


def _make_metadata() -> RecognitionUploadMetadata:
    return RecognitionUploadMetadata(
        filename="test.jpg",
        content_type="image/jpeg",
        prompt_version="card-recognition.md",
    )


class TestCornerCropToggle:
    """RecognitionService respects enable_corner_crop for debug artifact generation."""

    def test_debug_artifact_included_when_corner_crop_enabled(self, mock_provider):
        """corner_crop.jpg is present in debug_images when enable_corner_crop=True."""
        service = RecognitionService(mock_provider, enable_corner_crop=True)
        fake_corner = b"\xff\xd8\xff"  # minimal JPEG bytes

        with patch(
            "app.services.recognizer._generate_debug_images",
            return_value={"corner_crop.jpg": fake_corner},
        ) as mock_gen:
            result = service.recognize(image_bytes=b"img", metadata=_make_metadata())

        mock_gen.assert_called_once_with(b"img")
        assert "corner_crop.jpg" in result.debug_images

    def test_debug_artifact_skipped_when_corner_crop_disabled(self, mock_provider):
        """debug_images is empty when enable_corner_crop=False; crop generator not called."""
        service = RecognitionService(mock_provider, enable_corner_crop=False)

        with patch(
            "app.services.recognizer._generate_debug_images",
        ) as mock_gen:
            result = service.recognize(image_bytes=b"img", metadata=_make_metadata())

        mock_gen.assert_not_called()
        assert result.debug_images == {}
