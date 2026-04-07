import json
import sqlite3
from pathlib import Path

import pytest

from app.services.mtgjson_index import (
    MTGJSONImportError,
    MTGJSONIndex,
    import_all_printings,
    normalize_collector_number,
    normalize_set_code,
    normalize_set_name,
    normalize_title,
)


@pytest.fixture
def mtgjson_fixture_with_split(tmp_path: Path) -> Path:
    payload = {
        "meta": {"date": "2026-03-26", "version": "1.0.0"},
        "data": {
            "WAR": {
                "code": "WAR",
                "name": "War of the Spark",
                "releaseDate": "2019-05-03",
                "cards": [
                    {
                        "uuid": "warrant-warden-war-230",
                        "name": "Warrant // Warden",
                        "number": "230",
                        "layout": "split",
                        "language": "English",
                    },
                ],
            },
        },
    }
    path = tmp_path / "AllPrintings.split.json"
    path.write_text(json.dumps(payload))
    return path


@pytest.fixture
def mtgjson_fixture(tmp_path: Path) -> Path:
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
                        "setCode": "M10",
                        "number": "146",
                        "layout": "normal",
                        "language": "English",
                        "rarity": "common",
                        "type": "Instant",
                        "text": "Lightning Bolt deals 3 damage to any target.",
                        "manaCost": "{R}",
                        "identifiers": {"scryfallId": "e3285e6b-3e79-4d7c-bf96-d920f973b122"},
                        "purchaseUrls": {
                            "cardKingdom": "https://www.cardkingdom.com/mtg/magic-2010/lightning-bolt",
                            "cardKingdomFoil": "https://www.cardkingdom.com/mtg/magic-2010/lightning-bolt-foil",
                        },
                        "colorIdentity": ["R"],
                    },
                    {
                        "uuid": "forest-m10-247",
                        "name": "Forest",
                        "setCode": "M10",
                        "number": "247",
                        "layout": "normal",
                        "language": "English",
                        "rarity": "common",
                        "type": "Basic Land — Forest",
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
                        "layout": "normal",
                        "language": "English",
                        "rarity": "uncommon",
                        "type": "Instant",
                        "text": "Lightning Bolt deals 3 damage to any target.",
                        "manaCost": "{R}",
                        "identifiers": {"scryfallId": "f29ba16f-c8fb-42fe-aabf-87089cb214a7"},
                        "purchaseUrls": {
                            "cardKingdom": "https://www.cardkingdom.com/mtg/double-masters/lightning-bolt",
                        },
                    },
                    {
                        "uuid": "forest-2xm-247",
                        "name": "Forest",
                        "setCode": "2XM",
                        "number": "247",
                        "layout": "normal",
                        "language": "English",
                        "rarity": "common",
                        "type": "Basic Land — Forest",
                    },
                    {
                        "uuid": "skip-me",
                        "setCode": "2XM",
                        "number": "999",
                    },
                ],
            },
        },
    }
    path = tmp_path / "AllPrintings.fixture.json"
    path.write_text(json.dumps(payload))
    return path


def test_normalization_helpers() -> None:
    assert normalize_title("Lightning Bolt") == "lightning bolt"
    assert normalize_title("  Lightning—Bolt  ") == "lightning bolt"
    assert normalize_title("Lightning-Bolt") == "lightning bolt"
    assert normalize_title("Jace, the Mind Sculptor") == "jace the mind sculptor"
    assert normalize_title("Urza's Saga") == "urzas saga"
    assert normalize_set_code(" m10 ") == "M10"
    assert normalize_set_name("  Magic 2010 ") == "magic 2010"
    assert normalize_collector_number(" 001A ") == "1a"
    assert normalize_collector_number("007") == "7"


def test_import_all_printings_builds_sqlite_and_manifest(tmp_path: Path, mtgjson_fixture: Path) -> None:
    db_path = tmp_path / "mtgjson.sqlite"
    manifest_path = tmp_path / "manifest.json"

    summary = import_all_printings(
        source_path=mtgjson_fixture,
        db_path=db_path,
        manifest_path=manifest_path,
    )

    assert summary.set_count == 2
    assert summary.card_count == 4
    assert summary.skipped_card_count == 1
    assert db_path.exists()

    manifest = json.loads(manifest_path.read_text())
    assert manifest["total_set_count"] == 2
    assert manifest["total_card_printing_count"] == 4
    assert manifest["mtgjson_version"] == "1.0.0"

    with sqlite3.connect(db_path) as conn:
        set_count = conn.execute("SELECT COUNT(*) FROM sets").fetchone()[0]
        card_count = conn.execute("SELECT COUNT(*) FROM cards").fetchone()[0]
    assert set_count == 2
    assert card_count == 4


def test_import_all_printings_rejects_malformed_source(tmp_path: Path) -> None:
    source_path = tmp_path / "broken.json"
    source_path.write_text("{not-json")

    with pytest.raises(MTGJSONImportError):
        import_all_printings(
            source_path=source_path,
            db_path=tmp_path / "mtgjson.sqlite",
            manifest_path=tmp_path / "manifest.json",
        )


def test_index_lookup_paths(tmp_path: Path, mtgjson_fixture: Path) -> None:
    db_path = tmp_path / "mtgjson.sqlite"
    manifest_path = tmp_path / "manifest.json"
    import_all_printings(source_path=mtgjson_fixture, db_path=db_path, manifest_path=manifest_path)

    index = MTGJSONIndex(db_path)

    exact = index.lookup_exact(title="Lightning Bolt", set_code="M10", collector_number="146")
    assert exact is not None
    assert exact.uuid == "bolt-m10-146"

    assert index.resolve_set("Magic 2010") == "M10"
    assert index.resolve_set("m10") == "M10"

    by_name_set = index.lookup_by_name_and_set(title="Lightning Bolt", set_code="2XM")
    assert [card.uuid for card in by_name_set] == ["bolt-2xm-123"]

    by_name_number = index.lookup_by_name_and_number(title="Forest", collector_number="247")
    assert sorted(card.uuid for card in by_name_number) == ["forest-2xm-247", "forest-m10-247"]

    # Verify enriched fields on exact match
    assert exact.rarity == "common"
    assert exact.type_line == "Instant"
    assert exact.oracle_text == "Lightning Bolt deals 3 damage to any target."
    assert exact.scryfall_id == "e3285e6b-3e79-4d7c-bf96-d920f973b122"
    assert exact.card_kingdom_url == "https://www.cardkingdom.com/mtg/magic-2010/lightning-bolt"
    assert exact.card_kingdom_foil_url == "https://www.cardkingdom.com/mtg/magic-2010/lightning-bolt-foil"
    assert exact.mana_cost == "{R}"
    assert exact.power is None
    assert exact.toughness is None
    assert exact.color_identity == "R"

    # Verify land has no mana cost or color identity
    forest = index.lookup_exact(title="Forest", set_code="M10", collector_number="247")
    assert forest is not None
    assert forest.mana_cost is None
    assert forest.color_identity is None


def test_lookup_all_printings_by_name(tmp_path: Path, mtgjson_fixture: Path) -> None:
    db_path = tmp_path / "mtgjson.sqlite"
    manifest_path = tmp_path / "manifest.json"
    import_all_printings(source_path=mtgjson_fixture, db_path=db_path, manifest_path=manifest_path)

    index = MTGJSONIndex(db_path)
    printings = index.lookup_all_printings_by_name(title="Lightning Bolt")
    assert len(printings) == 2
    set_codes = [p.set_code for p in printings]
    assert "M10" in set_codes
    assert "2XM" in set_codes


def test_face_names_table_populated(tmp_path: Path, mtgjson_fixture_with_split: Path) -> None:
    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(source_path=mtgjson_fixture_with_split, db_path=db_path, manifest_path=tmp_path / "manifest.json")

    with sqlite3.connect(db_path) as conn:
        rows = conn.execute("SELECT face_name FROM face_names ORDER BY face_name").fetchall()
    face_names = [row[0] for row in rows]
    assert "Warrant" in face_names
    assert "Warden" in face_names


def test_lookup_by_face_name_finds_split_card(tmp_path: Path, mtgjson_fixture_with_split: Path) -> None:
    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(source_path=mtgjson_fixture_with_split, db_path=db_path, manifest_path=tmp_path / "manifest.json")

    index = MTGJSONIndex(db_path)
    results = index.lookup_by_face_name(title="Warrant")
    assert len(results) == 1
    assert results[0].name == "Warrant // Warden"
    assert results[0].uuid == "warrant-warden-war-230"


def test_lookup_by_face_name_finds_second_face(tmp_path: Path, mtgjson_fixture_with_split: Path) -> None:
    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(source_path=mtgjson_fixture_with_split, db_path=db_path, manifest_path=tmp_path / "manifest.json")

    index = MTGJSONIndex(db_path)
    results = index.lookup_by_face_name(title="Warden")
    assert len(results) == 1
    assert results[0].name == "Warrant // Warden"


def test_import_merges_split_card_face_metadata(tmp_path: Path) -> None:
    """MTGJSON stores each face of a split card as a separate record with the same name+set+number.
    The importer keeps one row but merges per-face type_line, oracle_text, and mana_cost."""
    payload = {
        "meta": {"date": "2026-03-26", "version": "1.0.0"},
        "data": {
            "RNA": {
                "code": "RNA",
                "name": "Ravnica Allegiance",
                "releaseDate": "2019-01-25",
                "cards": [
                    {
                        "uuid": "incubation-face1",
                        "name": "Incubation // Incongruity",
                        "number": "226",
                        "layout": "split",
                        "language": "English",
                        "type": "Sorcery",
                        "text": "Look at the top five cards.",
                        "manaCost": "{G}",
                    },
                    {
                        "uuid": "incubation-face2",
                        "name": "Incubation // Incongruity",
                        "number": "226",
                        "layout": "split",
                        "language": "English",
                        "type": "Instant",
                        "text": "Exile target creature.",
                        "manaCost": "{1}{U}",
                    },
                ],
            },
        },
    }
    source_path = tmp_path / "AllPrintings.json"
    source_path.write_text(json.dumps(payload))
    db_path = tmp_path / "mtgjson.sqlite"
    summary = import_all_printings(source_path=source_path, db_path=db_path, manifest_path=tmp_path / "manifest.json")

    assert summary.card_count == 1
    assert summary.skipped_card_count == 1

    index = MTGJSONIndex(db_path)
    results = index.lookup_by_name_and_set(title="Incubation // Incongruity", set_code="RNA")
    assert len(results) == 1
    card = results[0]
    assert card.type_line == "Sorcery // Instant"
    assert card.oracle_text is not None and "Look at the top five cards." in card.oracle_text
    assert card.oracle_text is not None and "Exile target creature." in card.oracle_text
    assert card.mana_cost == "{G} // {1}{U}"


def test_lookup_by_face_name_returns_empty_on_old_db_without_table(tmp_path: Path, mtgjson_fixture: Path) -> None:
    """Old databases without face_names table must not raise — return empty list."""
    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(source_path=mtgjson_fixture, db_path=db_path, manifest_path=tmp_path / "manifest.json")

    # Drop the face_names table to simulate an old database
    with sqlite3.connect(db_path) as conn:
        conn.execute("DROP TABLE IF EXISTS face_names")

    index = MTGJSONIndex(db_path)
    results = index.lookup_by_face_name(title="Lightning Bolt")
    assert results == []


def test_lookup_by_face_name_no_match_for_normal_card(tmp_path: Path, mtgjson_fixture: Path) -> None:
    db_path = tmp_path / "mtgjson.sqlite"
    import_all_printings(source_path=mtgjson_fixture, db_path=db_path, manifest_path=tmp_path / "manifest.json")

    index = MTGJSONIndex(db_path)
    results = index.lookup_by_face_name(title="Lightning Bolt")
    assert results == []
