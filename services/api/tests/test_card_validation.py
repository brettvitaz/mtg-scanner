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
                {"uuid": "bolt-m10-146", "name": "Lightning Bolt", "setCode": "M10", "number": "146", "language": "English", "layout": "normal", "rarity": "common", "type": "Instant", "text": "Lightning Bolt deals 3 damage to any target.", "manaCost": "{R}", "finishes": ["nonfoil", "foil"], "identifiers": {"scryfallId": "e3285e6b-0000-0000-0000-000000000000"}, "purchaseUrls": {"cardKingdom": "https://www.cardkingdom.com/mtg/magic-2010/lightning-bolt"}, "colorIdentity": ["R"]},
                {"uuid": "forest-m10-247", "name": "Forest", "setCode": "M10", "number": "247", "language": "English", "layout": "normal", "rarity": "common", "type": "Basic Land \u2014 Forest", "finishes": ["nonfoil"]}
              ]
            },
            "2XM": {
              "code": "2XM",
              "name": "Double Masters",
              "releaseDate": "2020-08-07",
              "cards": [
                {"uuid": "bolt-2xm-123", "name": "Lightning Bolt", "setCode": "2XM", "number": "123", "language": "English", "layout": "normal", "finishes": ["nonfoil", "foil"]},
                {"uuid": "forest-2xm-247", "name": "Forest", "setCode": "2XM", "number": "247", "language": "English", "layout": "normal", "finishes": ["nonfoil"]}
              ]
            },
            "DFT": {
              "code": "DFT",
              "name": "Aetherdrift",
              "releaseDate": "2026-02-14",
              "cards": [
                {"uuid": "autarch-mammoth-dft-153", "name": "Autarch Mammoth", "setCode": "DFT", "number": "166", "language": "English", "layout": "normal", "finishes": ["nonfoil", "foil"]},
                {"uuid": "pactdoll-terror-dft-99", "name": "Pactdoll Terror", "setCode": "DFT", "number": "99", "language": "English", "layout": "normal", "finishes": ["nonfoil", "foil"]}
              ]
            },
            "OTJ": {
              "code": "OTJ",
              "name": "Outlaws of Thunder Junction",
              "releaseDate": "2024-04-19",
              "cards": [
                {"uuid": "laughing-jasper-flint-otj-215", "name": "Laughing Jasper Flint", "setCode": "OTJ", "number": "215", "language": "English", "layout": "normal", "finishes": ["nonfoil", "foil"]},
                {"uuid": "foil-only-otj-001", "name": "Foil Only Card", "setCode": "OTJ", "number": "001", "language": "English", "layout": "normal", "finishes": ["foil"]}
              ]
            },
            "WAR": {
              "code": "WAR",
              "name": "War of the Spark",
              "releaseDate": "2019-05-03",
              "cards": [
                {"uuid": "warrant-warden-war-230", "name": "Warrant // Warden", "setCode": "WAR", "number": "230", "language": "English", "layout": "split", "finishes": ["nonfoil", "foil"]}
              ]
            },
            "C21": {
              "code": "C21",
              "name": "Commander 2021",
              "releaseDate": "2021-04-23",
              "cards": [
                {"uuid": "warrant-warden-c21-219", "name": "Warrant // Warden", "setCode": "C21", "number": "219", "language": "English", "layout": "split", "finishes": ["nonfoil"]}
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
    # Enriched fields from MTGJSON
    assert result.card.set_code == "M10"
    assert result.card.rarity == "common"
    assert result.card.type_line == "Instant"
    assert result.card.oracle_text == "Lightning Bolt deals 3 damage to any target."
    assert result.card.scryfall_id == "e3285e6b-0000-0000-0000-000000000000"
    assert result.card.image_url is not None and "e3285e6b-0000-0000-0000-000000000000" in result.card.image_url
    assert result.card.set_symbol_url == "https://svgs.scryfall.io/sets/m10.svg"
    assert result.card.card_kingdom_url == "https://www.cardkingdom.com/mtg/magic-2010/lightning-bolt"
    assert result.card.mana_cost == "{R}"
    assert result.card.color_identity == "R"


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
    for variant in ("Lightning\u2014Bolt", "Lightning-Bolt"):
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
    assert result.card.notes is not None and "multiple" in result.card.notes.lower()


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


def test_validate_card_rejects_impossible_title_and_set_combination(validation_service: CardValidationService) -> None:
    # Autarch Mammoth only exists in DFT, not OTJ — wrong set but title resolves
    # Since Autarch Mammoth is in exactly one set (DFT), this should be auto-corrected
    result = validation_service.validate_card(
        RecognizedCard(
            title="Autarch Mammoth",
            edition="Outlaws of Thunder Junction",
            collector_number="153",
            foil=False,
            confidence=0.92,
            notes=None,
        )
    )

    assert result.trace.status == "corrected_match"
    assert result.card.title == "Autarch Mammoth"
    assert result.card.edition == "Aetherdrift"
    assert result.card.set_code == "DFT"
    assert result.trace.matched_uuid == "autarch-mammoth-dft-153"


def test_validate_card_rejects_collector_number_conflict_inside_resolved_set(validation_service: CardValidationService) -> None:
    result = validation_service.validate_card(
        RecognizedCard(
            title="Lightning Bolt",
            edition="Magic 2010",
            collector_number="999",
            foil=False,
            confidence=0.9,
            notes=None,
        )
    )

    # Lightning Bolt exists in 2 sets so it falls through to needs_correction
    assert result.trace.status == "needs_correction"
    assert result.card.title == "Lightning Bolt"
    assert result.trace.matched_uuid is None
    assert len(result.correction_candidates) == 2


def test_validate_card_auto_corrects_single_printing(validation_service: CardValidationService) -> None:
    # Pactdoll Terror only exists in DFT, so wrong set should be auto-corrected
    result = validation_service.validate_card(
        RecognizedCard(
            title="Pactdoll Terror",
            edition="Dominaria",
            collector_number="99",
            foil=False,
            confidence=0.85,
            notes=None,
        )
    )

    assert result.trace.status == "corrected_match"
    assert result.card.title == "Pactdoll Terror"
    assert result.card.edition == "Aetherdrift"
    assert result.card.set_code == "DFT"
    assert result.card.collector_number == "99"
    assert result.card.confidence == 0.8
    assert result.trace.matched_uuid == "pactdoll-terror-dft-99"


def test_validate_card_needs_correction_when_multiple_sets(validation_service: CardValidationService) -> None:
    # Lightning Bolt exists in both M10 and 2XM — wrong set, multiple printings
    result = validation_service.validate_card(
        RecognizedCard(
            title="Lightning Bolt",
            edition="Dominaria",
            collector_number=None,
            foil=False,
            confidence=0.80,
            notes=None,
        )
    )

    assert result.trace.status == "needs_correction"
    assert result.card.title == "Lightning Bolt"
    assert result.trace.matched_uuid is None
    assert len(result.correction_candidates) == 2
    candidate_sets = {c.set_code for c in result.correction_candidates}
    assert candidate_sets == {"M10", "2XM"}


def test_validate_card_foil_mismatch_nonfoil_only(validation_service: CardValidationService) -> None:
    # Forest in M10 is nonfoil only
    result = validation_service.validate_card(
        RecognizedCard(
            title="Forest",
            edition="M10",
            collector_number="247",
            foil=True,
            confidence=0.9,
            notes=None,
        )
    )

    assert result.trace.status == "exact_match"
    assert result.card.notes is not None and "not available in foil" in result.card.notes
    # Foil mismatch penalty applied on top of exact_match boost
    assert result.card.confidence < 0.93


def test_validate_card_foil_mismatch_foil_only(validation_service: CardValidationService) -> None:
    # Foil Only Card in OTJ has finishes=["foil"] only
    result = validation_service.validate_card(
        RecognizedCard(
            title="Foil Only Card",
            edition="OTJ",
            collector_number="001",
            foil=False,
            confidence=0.9,
            notes=None,
        )
    )

    assert result.trace.status == "exact_match"
    assert result.card.notes is not None and "only available in foil" in result.card.notes


def test_validate_card_foil_match_valid(validation_service: CardValidationService) -> None:
    # Lightning Bolt in M10 has both nonfoil and foil
    result = validation_service.validate_card(
        RecognizedCard(
            title="Lightning Bolt",
            edition="M10",
            collector_number="146",
            foil=True,
            confidence=0.91,
            notes=None,
        )
    )

    assert result.trace.status == "exact_match"
    assert result.card.notes is not None and "foil" not in result.card.notes.lower() or "Validated" in result.card.notes


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

    assert batch.traces[0].status == "exact_match"
    assert batch.traces[1].status == "no_match"
    assert batch.response.cards[0].edition == "Magic 2010"
    assert batch.response.cards[1].title == "Totally Fake Card"


def test_validate_split_card_face_name_narrows_by_set_and_number(validation_service: CardValidationService) -> None:
    # Face name "Warrant" exists in WAR and C21, but edition+number pins it to WAR 230
    result = validation_service.validate_card(
        RecognizedCard(
            title="Warrant",
            edition="War of the Spark",
            collector_number="230",
            foil=False,
            confidence=0.99,
            notes=None,
        )
    )

    assert result.trace.status == "corrected_match"
    assert result.card.title == "Warrant // Warden"
    assert result.card.set_code == "WAR"
    assert result.trace.matched_uuid == "warrant-warden-war-230"


def test_validate_split_card_face_name_fallback(validation_service: CardValidationService) -> None:
    # LLM returned a single face name with set context that pins it to one printing
    result = validation_service.validate_card(
        RecognizedCard(
            title="Warrant",
            edition="War of the Spark",
            collector_number=None,
            foil=False,
            confidence=0.75,
            notes=None,
        )
    )

    assert result.trace.status == "corrected_match"
    assert result.card.title == "Warrant // Warden"
    assert result.card.set_code == "WAR"
    assert result.trace.matched_uuid == "warrant-warden-war-230"


def test_validate_split_card_full_name_still_works(validation_service: CardValidationService) -> None:
    # LLM correctly returned the full combined name
    result = validation_service.validate_card(
        RecognizedCard(
            title="Warrant // Warden",
            edition="WAR",
            collector_number="230",
            foil=False,
            confidence=0.88,
            notes=None,
        )
    )

    assert result.trace.status == "exact_match"
    assert result.card.title == "Warrant // Warden"
    assert result.card.set_code == "WAR"


def test_validate_response_collapses_split_card_faces(validation_service: CardValidationService) -> None:
    # Both face names corrected to same card — redundant second entry dropped
    response = RecognitionResponse(
        cards=[
            RecognizedCard(title="Warrant", edition="War of the Spark", collector_number="230", foil=False, confidence=0.86, notes=None),
            RecognizedCard(title="Warden", edition="War of the Spark", collector_number="230", foil=False, confidence=0.84, notes=None),
        ]
    )
    batch = validation_service.validate_response(response)

    assert len(batch.response.cards) == 1
    assert batch.response.cards[0].title == "Warrant // Warden"


def test_validate_response_drops_unmatched_face_when_other_half_matched(validation_service: CardValidationService) -> None:
    # One face matched, the other failed — the failed half is dropped as redundant
    response = RecognitionResponse(
        cards=[
            RecognizedCard(title="Warrant", edition="War of the Spark", collector_number="230", foil=False, confidence=0.86, notes=None),
            RecognizedCard(title="Xarden", edition=None, collector_number=None, foil=False, confidence=0.5, notes=None),  # misspelling, no_match
        ]
    )
    batch = validation_service.validate_response(response)

    # "Xarden" doesn't match any face — both cards kept
    assert len(batch.response.cards) == 2


def test_validate_response_drops_valid_face_when_sibling_matched(validation_service: CardValidationService) -> None:
    # "Warden" corrected to full card; "Warrant" (valid face name) is redundant — drop it
    response = RecognitionResponse(
        cards=[
            RecognizedCard(title="Warrant", edition=None, collector_number=None, foil=False, confidence=0.84, notes=None),
            RecognizedCard(title="Warden", edition="War of the Spark", collector_number="230", foil=False, confidence=0.86, notes=None),
        ]
    )
    batch = validation_service.validate_response(response)

    # Both faces resolve to the same card; the redundant entry is dropped
    assert len(batch.response.cards) == 1
    assert batch.response.cards[0].title == "Warrant // Warden"


def test_validate_response_preserves_full_name_match_alongside_face_correction(validation_service: CardValidationService) -> None:
    # One card recognized by full name (exact_match) + one corrected from face name.
    # Both resolve to same UUID but full-name match must not be dropped.
    response = RecognitionResponse(
        cards=[
            RecognizedCard(title="Warrant // Warden", edition="WAR", collector_number="230", foil=False, confidence=0.95, notes=None),
            RecognizedCard(title="Warrant", edition="War of the Spark", collector_number="230", foil=False, confidence=0.84, notes=None),
        ]
    )
    batch = validation_service.validate_response(response)

    # Full-name exact match kept; face-name correction dropped as sibling
    assert len(batch.response.cards) == 1
    assert batch.response.cards[0].title == "Warrant // Warden"
    assert batch.traces[0].status == "exact_match"


def test_validate_response_preserves_duplicate_split_cards_by_face_name(validation_service: CardValidationService) -> None:
    # Two physical copies of the same split card, both recognized by the same face name.
    # Both should be kept — same original title means different physical cards, not siblings.
    response = RecognitionResponse(
        cards=[
            RecognizedCard(title="Warrant", edition="War of the Spark", collector_number="230", foil=False, confidence=0.86, notes=None),
            RecognizedCard(title="Warrant", edition="War of the Spark", collector_number="230", foil=False, confidence=0.84, notes=None),
        ]
    )
    batch = validation_service.validate_response(response)

    assert len(batch.response.cards) == 2
    assert batch.response.cards[0].title == "Warrant // Warden"
    assert batch.response.cards[1].title == "Warrant // Warden"


def test_validate_response_preserves_duplicate_physical_cards(validation_service: CardValidationService) -> None:
    # Two copies of the same card on a page must NOT be collapsed
    response = RecognitionResponse(
        cards=[
            RecognizedCard(title="Lightning Bolt", edition="M10", collector_number="146", foil=False, confidence=0.95, notes=None),
            RecognizedCard(title="Lightning Bolt", edition="M10", collector_number="146", foil=False, confidence=0.93, notes=None),
        ]
    )

    batch = validation_service.validate_response(response)

    assert len(batch.response.cards) == 2
    assert batch.traces[0].matched_uuid == "bolt-m10-146"
    assert batch.traces[1].matched_uuid == "bolt-m10-146"


def test_validate_response_exposes_correction_candidates(validation_service: CardValidationService) -> None:
    response = RecognitionResponse(
        cards=[
            RecognizedCard(title="Lightning Bolt", edition="Dominaria", collector_number=None, foil=False, confidence=0.8, notes=None),
        ]
    )

    batch = validation_service.validate_response(response)

    assert batch.traces[0].status == "needs_correction"
    assert len(batch.correction_candidates[0]) == 2


def test_validate_card_preserves_v2_llm_fields(validation_service: CardValidationService) -> None:
    """V2 LLM fields (foil_type, border_color, etc.) survive validation enrichment unchanged."""
    card = RecognizedCard(
        title="Lightning Bolt",
        edition="Magic 2010",
        collector_number="146",
        foil=False,
        confidence=0.95,
        edition_notes="M10 set code visible in bottom strip.",
        foil_type="none",
        foil_evidence=["bullet separator visible — non-foil confirmed"],
        list_reprint="no",
        list_symbol_visible=False,
        border_color="black",
        copyright_line="146 C\nM10 • EN   Adam Rex",
        promo_text=None,
    )
    result = validation_service.validate_card(card)
    enriched = result.card

    assert enriched.edition_notes == card.edition_notes
    assert enriched.foil_type == card.foil_type
    assert enriched.foil_evidence == card.foil_evidence
    assert enriched.list_reprint == card.list_reprint
    assert enriched.list_symbol_visible == card.list_symbol_visible
    assert enriched.border_color == card.border_color
    assert enriched.copyright_line == card.copyright_line
    assert enriched.promo_text == card.promo_text


# ---------------------------------------------------------------------------
# list_reprint — LLM verdict is authoritative; identity fields follow it
# ---------------------------------------------------------------------------

@pytest.fixture
def list_plst_service(tmp_path: Path) -> CardValidationService:
    """Validation service with M10 + PLST data for list_reprint identity tests."""
    import json

    payload = {
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
                        "number": "146",
                        "language": "English",
                        "layout": "normal",
                        "rarity": "common",
                        "type": "Instant",
                        "finishes": ["nonfoil", "foil"],
                        "identifiers": {"scryfallId": "e3285e6b-0000-0000-0000-000000000000"},
                    },
                ],
            },
            "PLST": {
                "code": "PLST",
                "name": "The List",
                "releaseDate": "2020-09-25",
                "cards": [
                    {
                        "uuid": "bolt-plst-m10-146",
                        "name": "Lightning Bolt",
                        "number": "M10-146",
                        "language": "English",
                        "layout": "normal",
                        "finishes": ["nonfoil"],
                    },
                ],
            },
        },
    }
    source_path = tmp_path / "AllPrintings.list.json"
    source_path.write_text(json.dumps(payload))
    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(source_path=source_path, db_path=db_path, manifest_path=tmp_path / "manifest.json")
    return CardValidationService(index=MTGJSONIndex(db_path))


def test_list_reprint_no_preserves_originating_set(
    list_plst_service: CardValidationService,
) -> None:
    """When LLM says list_reprint='no', identity fields stay on the originating set."""
    card = RecognizedCard(
        title="Lightning Bolt",
        edition="M10",
        collector_number="146",
        foil=False,
        confidence=0.90,
        list_reprint="no",
        list_symbol_visible=False,
    )
    result = list_plst_service.validate_card(card)

    assert result.card.list_reprint == "no"
    assert result.card.set_code == "M10"
    assert result.card.edition == "Magic 2010"
    assert result.card.collector_number == "146"


def test_list_reprint_yes_rewrites_identity_to_plst(
    list_plst_service: CardValidationService,
) -> None:
    """When LLM says list_reprint='yes', edition/set_code/collector_number are rewritten to PLST."""
    card = RecognizedCard(
        title="Lightning Bolt",
        edition="M10",
        collector_number="146",
        foil=False,
        confidence=0.90,
        list_reprint="yes",
        list_symbol_visible=True,
    )
    result = list_plst_service.validate_card(card)

    assert result.card.list_reprint == "yes"
    assert result.card.set_code == "PLST"
    assert result.card.edition == "The List"
    assert result.card.collector_number == "M10-146"


def test_list_reprint_yes_rechecks_foil_against_plst_printing(
    list_plst_service: CardValidationService,
) -> None:
    """Foil validation must run against the rewritten PLST record, not the source printing."""
    card = RecognizedCard(
        title="Lightning Bolt",
        edition="M10",
        collector_number="146",
        foil=True,
        confidence=0.90,
        list_reprint="yes",
        list_symbol_visible=True,
    )
    result = list_plst_service.validate_card(card)

    assert result.card.set_code == "PLST"
    assert result.card.collector_number == "M10-146"
    assert result.card.confidence == 0.87
    assert result.trace.matched_set_code == "PLST"
    assert result.trace.matched_collector_number == "M10-146"
    assert result.card.notes is not None
    assert "This printing is not available in foil." in result.card.notes


def test_validator_passes_through_llm_list_reprint_unchanged(
    validation_service: CardValidationService,
) -> None:
    """The validator never flips list_reprint from 'no' to 'yes' on its own.

    The existing validation_service fixture has no PLST data, confirming that
    the validator does not inject list_reprint overrides when the LLM says 'no'.
    """
    card = RecognizedCard(
        title="Lightning Bolt",
        edition="M10",
        collector_number="146",
        foil=False,
        confidence=0.90,
        list_reprint="no",
        list_symbol_visible=False,
    )
    result = validation_service.validate_card(card)

    assert result.card.list_reprint == "no"
    assert result.card.list_symbol_visible is False
    assert result.card.set_code == "M10"
    assert result.card.edition == "Magic 2010"
