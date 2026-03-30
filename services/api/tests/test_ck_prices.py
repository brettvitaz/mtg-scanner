from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.services.ck_prices import CKPriceIndex, import_ck_prices

client = TestClient(app)

SAMPLE_DATA = [
    {
        "id": 1,
        "url": "https://www.cardkingdom.com/mtg/magic-2010/lightning-bolt",
        "name": "Lightning Bolt",
        "edition": "Magic 2010",
        "is_foil": "false",
        "price_retail": "3.49",
        "qty_retail": 12,
        "price_buy": "2.00",
        "qty_buying": 20,
    },
    {
        "id": 2,
        "url": "https://www.cardkingdom.com/mtg/magic-2010/lightning-bolt-foil",
        "name": "Lightning Bolt",
        "edition": "Magic 2010",
        "is_foil": "true",
        "price_retail": "14.99",
        "qty_retail": 3,
        "price_buy": "8.00",
        "qty_buying": 5,
    },
    {
        "id": 3,
        "url": "https://www.cardkingdom.com/mtg/double-masters/lightning-bolt",
        "name": "Lightning Bolt",
        "edition": "Double Masters",
        "is_foil": "false",
        "price_retail": "2.99",
        "qty_retail": 8,
        "price_buy": "1.50",
        "qty_buying": 15,
    },
]


def _build_db(tmp_path: Path) -> Path:
    db_path = tmp_path / "ck_prices.sqlite"
    import_ck_prices(data=SAMPLE_DATA, db_path=db_path)
    return db_path


def test_import_creates_db_and_returns_summary(tmp_path: Path) -> None:
    db_path = tmp_path / "ck_prices.sqlite"
    summary = import_ck_prices(data=SAMPLE_DATA, db_path=db_path)
    assert summary.total_count == 3
    assert summary.skipped_count == 0
    assert db_path.exists()


def test_import_skips_entries_missing_name_or_edition(tmp_path: Path) -> None:
    bad_data = [{"id": 99}, {"id": 100, "name": "Bolt"}]
    summary = import_ck_prices(data=bad_data, db_path=tmp_path / "ck.sqlite")
    assert summary.total_count == 0
    assert summary.skipped_count == 2


def test_lookup_finds_normal_card(tmp_path: Path) -> None:
    db_path = _build_db(tmp_path)
    index = CKPriceIndex(db_path)
    result = index.lookup_price(name="Lightning Bolt", edition="Magic 2010")
    assert result is not None
    assert result.price_retail == "3.49"
    assert result.qty_retail == 12
    assert result.price_buy == "2.00"
    assert result.qty_buying == 20
    assert result.url == "https://www.cardkingdom.com/mtg/magic-2010/lightning-bolt"


def test_lookup_finds_foil_card(tmp_path: Path) -> None:
    db_path = _build_db(tmp_path)
    index = CKPriceIndex(db_path)
    result = index.lookup_price(
        name="Lightning Bolt", edition="Magic 2010", is_foil=True,
    )
    assert result is not None
    assert result.price_retail == "14.99"


def test_lookup_falls_back_to_name_only_when_edition_differs(tmp_path: Path) -> None:
    db_path = _build_db(tmp_path)
    index = CKPriceIndex(db_path)
    # MTGJSON uses "Magic 2010" but CK uses different names — should still find by name
    result = index.lookup_price(name="Lightning Bolt", edition="Totally Different Name")
    assert result is not None
    # Should pick the cheapest retail price (Double Masters at $2.99)
    assert result.price_retail == "2.99"


def test_lookup_returns_none_for_missing_card(tmp_path: Path) -> None:
    db_path = _build_db(tmp_path)
    index = CKPriceIndex(db_path)
    result = index.lookup_price(name="Nonexistent Card", edition="Magic 2010")
    assert result is None


def test_lookup_is_case_insensitive(tmp_path: Path) -> None:
    db_path = _build_db(tmp_path)
    index = CKPriceIndex(db_path)
    result = index.lookup_price(name="lightning bolt", edition="magic 2010")
    assert result is not None
    assert result.price_retail == "3.49"


def test_lookup_returns_none_when_db_missing(tmp_path: Path) -> None:
    index = CKPriceIndex(tmp_path / "missing.sqlite")
    assert not index.is_available()
    result = index.lookup_price(name="Lightning Bolt", edition="Magic 2010")
    assert result is None


def test_price_endpoint_returns_price(tmp_path: Path) -> None:
    db_path = _build_db(tmp_path)
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_enable_ck_prices = True
        mock_settings.return_value.mtg_scanner_ck_prices_db_path = str(db_path)
        resp = client.get(
            "/api/v1/cards/price",
            params={"name": "Lightning Bolt", "edition": "Magic 2010"},
        )

    assert resp.status_code == 200
    data = resp.json()
    assert data["price_retail"] == "3.49"
    assert data["price_buy"] == "2.00"


def test_price_endpoint_returns_503_when_disabled() -> None:
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_enable_ck_prices = False
        resp = client.get(
            "/api/v1/cards/price",
            params={"name": "Lightning Bolt", "edition": "Magic 2010"},
        )

    assert resp.status_code == 503


def test_price_endpoint_returns_empty_for_unknown_card(tmp_path: Path) -> None:
    db_path = _build_db(tmp_path)
    with patch("app.api.routes.cards.get_settings") as mock_settings:
        mock_settings.return_value.mtg_scanner_enable_ck_prices = True
        mock_settings.return_value.mtg_scanner_ck_prices_db_path = str(db_path)
        resp = client.get(
            "/api/v1/cards/price",
            params={"name": "Fake Card", "edition": "Fake Set"},
        )

    assert resp.status_code == 200
    data = resp.json()
    assert data["price_retail"] is None
    assert data["price_buy"] is None
