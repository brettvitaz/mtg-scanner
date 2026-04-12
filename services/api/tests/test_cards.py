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
                                "finishes": ["nonfoil", "foil"],
                                "identifiers": {"scryfallId": "e3285e6b-0000-0000-0000-000000000000"},
                                "purchaseUrls": {"cardKingdom": "https://www.cardkingdom.com/bolt-m10"},
                            },
                            {
                                "uuid": "aim-m10-247",
                                "name": "Steady Aim",
                                "setCode": "M10",
                                "number": "247",
                                "language": "English",
                                "layout": "normal",
                                "rarity": "common",
                                "type": "Instant",
                                "finishes": ["nonfoil"],
                                "identifiers": {"scryfallId": "aaaaaaaa-0000-0000-0000-000000000000"},
                            },
                            {
                                "uuid": "masterful-m10-248",
                                "name": "Masterful Aid",
                                "setCode": "M10",
                                "number": "248",
                                "language": "English",
                                "layout": "normal",
                                "rarity": "common",
                                "type": "Instant",
                                "finishes": ["nonfoil"],
                                "identifiers": {"scryfallId": "cccccccc-0000-0000-0000-000000000000"},
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
                                "finishes": ["nonfoil", "foil"],
                                "identifiers": {"scryfallId": "f29ba16f-0000-0000-0000-000000000000"},
                            },
                            {
                                "uuid": "foil-only-2xm-001",
                                "name": "Foil Only Card",
                                "setCode": "2XM",
                                "number": "001",
                                "language": "English",
                                "layout": "normal",
                                "rarity": "mythic",
                                "finishes": ["foil"],
                                "identifiers": {"scryfallId": "bbbbbbbb-0000-0000-0000-000000000000"},
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


# MARK: - finishes field


def test_get_printings_includes_finishes_nonfoil_foil(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/printings", params={"name": "Lightning Bolt"})

    assert resp.status_code == 200
    m10 = next(p for p in resp.json()["printings"] if p["set_code"] == "M10")
    assert m10["finishes"] == "nonfoil,foil"


def test_get_printings_includes_finishes_foil_only(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/printings", params={"name": "Foil Only Card"})

    assert resp.status_code == 200
    printings = resp.json()["printings"]
    assert len(printings) == 1
    assert printings[0]["finishes"] == "foil"


def test_get_printings_includes_finishes_nonfoil_only(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/printings", params={"name": "Steady Aim"})

    assert resp.status_code == 200
    printings = resp.json()["printings"]
    assert len(printings) == 1
    assert printings[0]["finishes"] == "nonfoil"


# MARK: - multi-token search


def test_search_card_names_multi_token_matches(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/search", params={"q": "light bolt"})

    assert resp.status_code == 200
    assert "Lightning Bolt" in resp.json()["names"]


def test_search_card_names_partial_multi_token(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/search", params={"q": "ste ai"})

    assert resp.status_code == 200
    assert "Steady Aim" in resp.json()["names"]


def test_search_card_names_multi_token_prefix_first_ordering(mtgjson_db: Path) -> None:
    # "ste ai" matches both "Steady Aim" (starts with "ste") and "Masterful Aid"
    # (contains "ste" mid-word). "Steady Aim" must appear first.
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/search", params={"q": "ste ai"})

    assert resp.status_code == 200
    names = resp.json()["names"]
    assert "Steady Aim" in names
    assert "Masterful Aid" in names
    assert names.index("Steady Aim") < names.index("Masterful Aid")


def test_search_card_names_multi_token_no_match(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/search", params={"q": "zzz bolt"})

    assert resp.status_code == 200
    assert resp.json()["names"] == []


def test_search_card_names_single_token_still_prefix(mtgjson_db: Path) -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_mtgjson_db_path = str(mtgjson_db)
        resp = client.get("/api/v1/cards/search", params={"q": "light"})

    assert resp.status_code == 200
    names = resp.json()["names"]
    assert "Lightning Bolt" in names
    # Prefix match: "Steady Aim" does not start with "light"
    assert "Steady Aim" not in names
