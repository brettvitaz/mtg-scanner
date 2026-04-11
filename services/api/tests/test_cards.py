import json
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services.mtgjson_index import import_all_printings

client = TestClient(app)


@pytest.fixture
def mtgjson_db(tmp_path: Path) -> Path:
    source_path = tmp_path / "AllPrintings.fixture.json"
    source_path.write_text(
        json.dumps(
            {
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
                                "setCode": "M10",
                                "number": "146",
                                "language": "English",
                                "layout": "normal",
                                "rarity": "common",
                                "type": "Instant",
                                "text": "Lightning Bolt deals 3 damage to any target.",
                                "manaCost": "{R}",
                                "identifiers": {"scryfallId": "e3285e6b-0000-0000-0000-000000000000"},
                                "purchaseUrls": {"cardKingdom": "https://www.cardkingdom.com/bolt-m10"},
                            },
                        ],
                    },
                    "2XM": {
                        "code": "2XM",
                        "name": "Double Masters",
                        "releaseDate": "2020-08-07",
                        "cards": [
                            {
                                "uuid": "bolt-2xm-123",
                                "name": "Lightning Bolt",
                                "setCode": "2XM",
                                "number": "123",
                                "language": "English",
                                "layout": "normal",
                                "rarity": "uncommon",
                                "type": "Instant",
                                "text": "Lightning Bolt deals 3 damage to any target.",
                                "manaCost": "{R}",
                                "identifiers": {"scryfallId": "f29ba16f-0000-0000-0000-000000000000"},
                            },
                        ],
                    },
                },
            }
        )
    )
    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(
        source_path=source_path,
        db_path=db_path,
        manifest_path=tmp_path / "manifest.json",
    )
    return db_path


def test_get_printings_returns_all_printings(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/printings", params={"name": "Lightning Bolt"})

    assert resp.status_code == 200
    data = resp.json()
    assert len(data["printings"]) == 2
    set_codes = {p["set_code"] for p in data["printings"]}
    assert set_codes == {"M10", "2XM"}

    m10 = next(p for p in data["printings"] if p["set_code"] == "M10")
    assert m10["rarity"] == "common"
    assert m10["type_line"] == "Instant"
    assert m10["oracle_text"] == "Lightning Bolt deals 3 damage to any target."
    assert m10["image_url"] is not None
    assert m10["set_symbol_url"] == "https://svgs.scryfall.io/sets/m10.svg"
    assert m10["card_kingdom_url"] == "https://www.cardkingdom.com/bolt-m10"
    assert m10["mana_cost"] == "{R}"


def test_get_printings_returns_empty_list_for_unknown_card(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/printings", params={"name": "Nonexistent Card"})

    assert resp.status_code == 200
    assert resp.json()["printings"] == []


def test_get_printings_returns_503_when_db_missing(tmp_path: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(tmp_path / "missing.sqlite")
        resp = client.get("/api/v1/cards/printings", params={"name": "Lightning Bolt"})

    assert resp.status_code == 503


def test_search_card_names_returns_matching_names(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/search", params={"q": "Light"})

    assert resp.status_code == 200
    assert resp.json()["names"] == ["Lightning Bolt"]


def test_search_card_names_deduplicates_across_sets(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/search", params={"q": "Lightning"})

    assert resp.status_code == 200
    assert resp.json()["names"].count("Lightning Bolt") == 1


def test_search_card_names_returns_empty_for_no_match(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/search", params={"q": "Zzzzz"})

    assert resp.status_code == 200
    assert resp.json()["names"] == []


def test_search_card_names_returns_503_when_db_missing(tmp_path: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(tmp_path / "missing.sqlite")
        resp = client.get("/api/v1/cards/search", params={"q": "Lightning"})

    assert resp.status_code == 503


def test_search_card_names_rejects_short_query() -> None:
    resp = client.get("/api/v1/cards/search", params={"q": "L"})
    assert resp.status_code == 422


def test_lookup_by_set_and_number_returns_card(mtgjson_db: Path) -> None:
    from app.services.mtgjson_index import MTGJSONIndex

    index = MTGJSONIndex(mtgjson_db)
    record = index.lookup_by_set_and_number(set_code="M10", collector_number="146")
    assert record is not None
    assert record.name == "Lightning Bolt"
    assert record.set_code == "M10"


def test_lookup_by_set_and_number_returns_none_when_not_found(mtgjson_db: Path) -> None:
    from app.services.mtgjson_index import MTGJSONIndex

    index = MTGJSONIndex(mtgjson_db)
    record = index.lookup_by_set_and_number(set_code="M10", collector_number="999")
    assert record is None
