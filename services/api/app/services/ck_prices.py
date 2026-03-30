from __future__ import annotations

import sqlite3
import unicodedata
from dataclasses import dataclass
from pathlib import Path


_SELECT_COLS = "price_retail, qty_retail, price_buy, qty_buying, url"


@dataclass(frozen=True, slots=True)
class CKPriceResult:
    price_retail: str | None
    qty_retail: int | None
    price_buy: str | None
    qty_buying: int | None
    url: str | None


@dataclass(frozen=True, slots=True)
class CKImportSummary:
    total_count: int
    skipped_count: int


class CKPriceIndex:
    def __init__(self, db_path: Path, *, base_url: str = "https://www.cardkingdom.com/") -> None:
        self._db_path = db_path
        self._base_url = base_url.rstrip("/")

    def is_available(self) -> bool:
        return self._db_path.is_file()

    def lookup_price(
        self,
        *,
        scryfall_id: str | None = None,
        name: str | None = None,
        is_foil: bool = False,
    ) -> CKPriceResult | None:
        if not self.is_available():
            return None
        foil_int = 1 if is_foil else 0
        try:
            with sqlite3.connect(self._db_path) as conn:
                row = None
                if scryfall_id:
                    row = conn.execute(
                        f"SELECT {_SELECT_COLS} FROM ck_prices"
                        " WHERE scryfall_id = ? AND is_foil = ? LIMIT 1",
                        (scryfall_id, foil_int),
                    ).fetchone()
                if row is None and name:
                    row = conn.execute(
                        f"SELECT {_SELECT_COLS} FROM ck_prices"
                        " WHERE normalized_name = ? AND is_foil = ?"
                        " ORDER BY CAST(price_retail AS REAL) ASC LIMIT 1",
                        (_normalize(name), foil_int),
                    ).fetchone()
        except sqlite3.DatabaseError:
            return None
        if row is None:
            return None
        url = row[4]
        if url and not url.startswith("http"):
            url = f"{self._base_url}/{url}"
        return CKPriceResult(
            price_retail=row[0],
            qty_retail=row[1],
            price_buy=row[2],
            qty_buying=row[3],
            url=url,
        )


def _normalize(value: str) -> str:
    return unicodedata.normalize("NFKC", value).strip().lower()


def create_ck_schema(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db_path) as conn:
        conn.executescript(
            """
            DROP TABLE IF EXISTS ck_prices;

            CREATE TABLE ck_prices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                scryfall_id TEXT,
                name TEXT NOT NULL,
                normalized_name TEXT NOT NULL,
                edition TEXT NOT NULL,
                is_foil INTEGER NOT NULL,
                price_retail TEXT,
                qty_retail INTEGER,
                price_buy TEXT,
                qty_buying INTEGER,
                url TEXT
            );

            CREATE INDEX idx_ck_scryfall ON ck_prices(scryfall_id, is_foil);
            CREATE INDEX idx_ck_name ON ck_prices(normalized_name, is_foil);
            """
        )


def import_ck_prices(
    *,
    data: list[dict[str, object]],
    db_path: Path,
) -> CKImportSummary:
    create_ck_schema(db_path)
    total = 0
    skipped = 0
    with sqlite3.connect(db_path) as conn:
        for entry in data:
            name = entry.get("name")
            edition = entry.get("edition")
            if not isinstance(name, str) or not isinstance(edition, str):
                skipped += 1
                continue
            is_foil = 1 if entry.get("is_foil") == "true" else 0
            conn.execute(
                "INSERT INTO ck_prices"
                " (scryfall_id, name, normalized_name, edition,"
                "  is_foil, price_retail, qty_retail, price_buy, qty_buying, url)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    entry.get("scryfall_id"),
                    name,
                    _normalize(name),
                    edition,
                    is_foil,
                    entry.get("price_retail"),
                    _safe_int(entry.get("qty_retail")),
                    entry.get("price_buy"),
                    _safe_int(entry.get("qty_buying")),
                    entry.get("url"),
                ),
            )
            total += 1
        conn.commit()
    return CKImportSummary(total_count=total, skipped_count=skipped)


def _safe_int(value: object) -> int | None:
    if value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return None
    return None
