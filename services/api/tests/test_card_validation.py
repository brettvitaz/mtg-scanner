from pathlib import Path

import pytest

from app.models.recognition import RecognizedCard, RecognitionResponse
from app.services.card_validation import CardValidationService
from app.services.mtgjson_index import MTGJSONIndex, import_all_printings


@pytest.fixture
def validation_service(tmp_path: Path) -> CardValidationService:
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
                {"uuid": "bolt-m10-146", "name": "Lightning Bolt", "setCode": "M10", "number": "146", "language": "English", "layout": "normal"},
                {"uuid": "forest-m10-247", "name": "Forest", "setCode": "M10", "number": "247", "language": "English", "layout": "normal"}
              ]
            },
            "2XM": {
              "code": "2XM",
              "name": "Double Masters",
              "releaseDate": "2020-08-07",
              "cards": [
                {"uuid": "bolt-2xm-123", "name": "Lightning Bolt", "setCode": "2XM", "number": "123", "language": "English", "layout": "normal"},
                {"uuid": "forest-2xm-247", "name": "Forest", "setCode": "2XM", "number": "247", "language": "English", "layout": "normal"}
              ]
            }
          }
        }
        """
    )
    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(source_path=source_path, db_path=db_path, manifest_path=tmp_path / "manifest.json")
    return CardValidationService(index=MTGJSONIndex(db_path))


def test_validate_card_exact_match(validation_service: CardValidationService) -> None:
    result = validation_service.validate_card(
        RecognizedCard(
            title="Lightning Bolt",
            edition="M10",
            collector_number="146",
            foil=False,
            confidence=0.91,
            notes="Raw recognizer output.",
        )
    )

    assert result.card.title == "Lightning Bolt"
    assert result.card.edition == "Magic 2010"
    assert result.card.collector_number == "146"
    assert result.card.confidence == 0.93
    assert result.trace.status == "exact_match"
    assert result.trace.matched_uuid == "bolt-m10-146"


def test_validate_card_resolves_set_name(validation_service: CardValidationService) -> None:
    result = validation_service.validate_card(
        RecognizedCard(
            title="Lightning Bolt",
            edition="Magic 2010",
            collector_number="146",
            foil=False,
            confidence=0.88,
            notes=None,
        )
    )

    assert result.card.edition == "Magic 2010"
    assert result.trace.status == "exact_match"


def test_validate_card_matches_common_punctuation_variants(validation_service: CardValidationService) -> None:
    for variant in ("Lightning—Bolt", "Lightning-Bolt"):
        result = validation_service.validate_card(
            RecognizedCard(
                title=variant,
                edition="M10",
                collector_number="146",
                foil=False,
                confidence=0.9,
                notes=None,
            )
        )

        assert result.card.title == "Lightning Bolt"
        assert result.card.edition == "Magic 2010"
        assert result.trace.status == "exact_match"


def test_validate_card_handles_ambiguous_match(validation_service: CardValidationService) -> None:
    result = validation_service.validate_card(
        RecognizedCard(
            title="Forest",
            edition=None,
            collector_number="247",
            foil=False,
            confidence=0.8,
            notes="OCR uncertain.",
        )
    )

    assert result.trace.status == "ambiguous_match"
    assert result.card.title == "Forest"
    assert result.card.confidence == 0.6
    assert "multiple" in result.card.notes.lower()


def test_validate_card_handles_no_match(validation_service: CardValidationService) -> None:
    result = validation_service.validate_card(
        RecognizedCard(
            title="Totally Fake Card",
            edition="M10",
            collector_number="999",
            foil=False,
            confidence=0.7,
            notes=None,
        )
    )

    assert result.trace.status == "no_match"
    assert result.card.confidence == 0.45
    assert "no mtgjson match" in result.card.notes.lower()


def test_validate_response_gracefully_skips_when_db_missing(tmp_path: Path) -> None:
    service = CardValidationService(index=MTGJSONIndex(tmp_path / "missing.sqlite"))
    response = RecognitionResponse(cards=[RecognizedCard(title="Lightning Bolt", edition="M10", collector_number="146", foil=False, confidence=0.9, notes=None)])

    batch = service.validate_response(response)

    assert batch.response == response
    assert batch.available is False
    assert batch.traces[0].status == "validation_unavailable"


def test_validate_response_gracefully_skips_when_db_corrupt(tmp_path: Path) -> None:
    corrupt_db = tmp_path / "corrupt.sqlite"
    corrupt_db.write_text("this is not a sqlite database")
    service = CardValidationService(index=MTGJSONIndex(corrupt_db))
    response = RecognitionResponse(cards=[RecognizedCard(title="Lightning Bolt", edition="M10", collector_number="146", foil=False, confidence=0.9, notes=None)])

    batch = service.validate_response(response)

    assert batch.response == response
    assert batch.available is False
    assert batch.traces[0].status == "validation_unavailable"
    assert "unreadable" in batch.traces[0].reason.lower()


def test_validate_response_validates_each_card_independently(validation_service: CardValidationService) -> None:
    response = RecognitionResponse(
        cards=[
            RecognizedCard(title="Lightning Bolt", edition="Magic 2010", collector_number="146", foil=False, confidence=0.9, notes=None),
            RecognizedCard(title="Totally Fake Card", edition="Magic 2010", collector_number="999", foil=False, confidence=0.8, notes=None),
        ]
    )

    batch = validation_service.validate_response(response)

    assert [trace.status for trace in batch.traces] == ["exact_match", "no_match"]
    assert batch.response.cards[0].edition == "Magic 2010"
    assert batch.response.cards[1].title == "Totally Fake Card"
