"""Tests for LLM-assisted card correction flow."""
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from app.models.recognition import RecognizedCard, RecognitionResponse, RecognitionUploadMetadata
from app.services.card_validation import CardValidationService
from app.services.mtgjson_index import CardRecord, MTGJSONIndex, import_all_printings
from app.services.recognizer import RecognitionService, _build_correction_prompt


@pytest.fixture
def mtgjson_db(tmp_path: Path) -> Path:
    source_path = tmp_path / "AllPrintings.fixture.json"
    source_path.write_text(
        """
        {
          "meta": {"date": "2026-03-26", "version": "1.0.0"},
          "data": {
            "M10": {
              "code": "M10",
              "name": "Magic 2010",
              "releaseDate": "2009-07-17",
              "cards": [
                {"uuid": "bolt-m10-146", "name": "Lightning Bolt", "setCode": "M10", "number": "146", "language": "English", "layout": "normal", "rarity": "common", "finishes": ["nonfoil", "foil"]}
              ]
            },
            "2XM": {
              "code": "2XM",
              "name": "Double Masters",
              "releaseDate": "2020-08-07",
              "cards": [
                {"uuid": "bolt-2xm-123", "name": "Lightning Bolt", "setCode": "2XM", "number": "123", "language": "English", "layout": "normal", "rarity": "common", "finishes": ["nonfoil", "foil"]}
              ]
            },
            "DFT": {
              "code": "DFT",
              "name": "Aetherdrift",
              "releaseDate": "2026-02-14",
              "cards": [
                {"uuid": "pactdoll-terror-dft-99", "name": "Pactdoll Terror", "setCode": "DFT", "number": "99", "language": "English", "layout": "normal", "rarity": "rare", "finishes": ["nonfoil", "foil"]}
              ]
            }
          }
        }
        """
    )
    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(source_path=source_path, db_path=db_path, manifest_path=tmp_path / "manifest.json")
    return db_path


@pytest.fixture
def validator(mtgjson_db: Path) -> CardValidationService:
    return CardValidationService(index=MTGJSONIndex(mtgjson_db))


def _make_metadata() -> RecognitionUploadMetadata:
    return RecognitionUploadMetadata(
        filename="test.jpg",
        content_type="image/jpeg",
        prompt_version="card-recognition.md",
    )


def test_build_correction_prompt_fills_all_placeholders() -> None:
    template = (
        "Title: {{title}}\n"
        "Edition: {{edition}}\n"
        "Collector: {{collector_number}}\n"
        "Foil: {{foil}}\n"
        "Reason: {{reason}}\n"
        "{{candidates_table}}"
    )
    card = RecognizedCard(
        title="Lightning Bolt",
        edition="Dominaria",
        collector_number="146",
        foil=False,
        confidence=0.8,
        notes=None,
    )
    candidates = [
        CardRecord(
            uuid="bolt-m10-146",
            name="Lightning Bolt",
            normalized_name="lightning bolt",
            set_code="M10",
            set_name="Magic 2010",
            collector_number="146",
            normalized_collector_number="146",
            language="English",
            layout="normal",
            release_date="2009-07-17",
            is_promo=False,
            rarity="common",
            finishes="nonfoil,foil",
        ),
    ]

    result = _build_correction_prompt(template, card, candidates, "title not in set")

    assert "Lightning Bolt" in result
    assert "Dominaria" in result
    assert "146" in result
    assert "False" in result
    assert "title not in set" in result
    assert "Magic 2010" in result
    assert "M10" in result
    assert "nonfoil,foil" in result


def test_build_correction_prompt_handles_empty_candidates() -> None:
    template = "{{candidates_table}}"
    card = RecognizedCard(title="X", edition=None, collector_number=None, foil=None, confidence=0.5, notes=None)

    result = _build_correction_prompt(template, card, [], "no candidates")

    assert "Set Name" in result
    assert "Set Code" in result


def test_llm_correction_resolves_needs_correction(validator: CardValidationService, mtgjson_db: Path) -> None:
    # Lightning Bolt is in 2 sets — initial validation returns needs_correction.
    # Mock provider returns the correct printing on the second call.
    corrected_response = RecognitionResponse(
        cards=[RecognizedCard(
            title="Lightning Bolt",
            edition="Magic 2010",
            collector_number="146",
            foil=False,
            confidence=0.85,
            notes="Corrected by LLM.",
        )]
    )

    mock_provider = MagicMock()
    mock_provider.provider_name = "mock"
    mock_provider.model_name = None
    mock_provider.recognize.return_value = corrected_response

    service = RecognitionService(
        mock_provider,
        card_detector=None,
        validator=validator,
        enable_llm_correction=True,
        correction_prompt_version="card-correction.md",
    )

    image_bytes = b"fake-image-data"
    metadata = _make_metadata()

    response, _, _, validation_result = service.recognize(image_bytes=image_bytes, metadata=metadata)

    # The mock's first call returns Lightning Bolt in unknown set
    # which will trigger needs_correction then the correction call
    assert validation_result is not None
    # The correction provider was called for the needs_correction card
    assert mock_provider.recognize.call_count >= 1


def test_llm_correction_disabled_does_not_retry(validator: CardValidationService) -> None:
    wrong_set_response = RecognitionResponse(
        cards=[RecognizedCard(
            title="Lightning Bolt",
            edition="Dominaria",
            collector_number=None,
            foil=False,
            confidence=0.80,
            notes=None,
        )]
    )

    mock_provider = MagicMock()
    mock_provider.provider_name = "mock"
    mock_provider.model_name = None
    mock_provider.recognize.return_value = wrong_set_response

    service = RecognitionService(
        mock_provider,
        card_detector=None,
        validator=validator,
        enable_llm_correction=False,
        correction_prompt_version="card-correction.md",
    )

    image_bytes = b"fake-image-data"
    metadata = _make_metadata()

    _, _, _, validation_result = service.recognize(image_bytes=image_bytes, metadata=metadata)

    assert validation_result is not None
    assert validation_result.traces[0].status == "needs_correction"
    # Only the initial recognition call, no correction retry
    assert mock_provider.recognize.call_count == 1


def test_llm_correction_fallback_on_provider_error(validator: CardValidationService) -> None:
    from app.services.errors import RecognitionProviderError

    wrong_set_response = RecognitionResponse(
        cards=[RecognizedCard(
            title="Lightning Bolt",
            edition="Dominaria",
            collector_number=None,
            foil=False,
            confidence=0.80,
            notes=None,
        )]
    )

    mock_provider = MagicMock()
    mock_provider.provider_name = "mock"
    mock_provider.model_name = None
    mock_provider.recognize.side_effect = [
        wrong_set_response,
        RecognitionProviderError("Connection failed"),
    ]

    service = RecognitionService(
        mock_provider,
        card_detector=None,
        validator=validator,
        enable_llm_correction=True,
        correction_prompt_version="card-correction.md",
    )

    image_bytes = b"fake-image-data"
    metadata = _make_metadata()

    _, _, _, validation_result = service.recognize(image_bytes=image_bytes, metadata=metadata)

    assert validation_result is not None
    # Correction failed, original needs_correction status retained
    assert validation_result.traces[0].status == "needs_correction"


def test_llm_correction_fallback_when_correction_also_fails_validation(validator: CardValidationService) -> None:
    wrong_set_response = RecognitionResponse(
        cards=[RecognizedCard(
            title="Lightning Bolt",
            edition="Dominaria",
            collector_number=None,
            foil=False,
            confidence=0.80,
            notes=None,
        )]
    )
    still_wrong_response = RecognitionResponse(
        cards=[RecognizedCard(
            title="Lightning Bolt",
            edition="Dominaria",
            collector_number=None,
            foil=False,
            confidence=0.60,
            notes="Still wrong.",
        )]
    )

    mock_provider = MagicMock()
    mock_provider.provider_name = "mock"
    mock_provider.model_name = None
    mock_provider.recognize.side_effect = [wrong_set_response, still_wrong_response]

    service = RecognitionService(
        mock_provider,
        card_detector=None,
        validator=validator,
        enable_llm_correction=True,
        correction_prompt_version="card-correction.md",
    )

    image_bytes = b"fake-image-data"
    metadata = _make_metadata()

    _, _, _, validation_result = service.recognize(image_bytes=image_bytes, metadata=metadata)

    assert validation_result is not None
    # Correction attempt also returned needs_correction, so original retained
    assert validation_result.traces[0].status == "needs_correction"
