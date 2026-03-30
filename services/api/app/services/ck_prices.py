from __future__ import annotations

import sqlite3
import unicodedata
from dataclasses import dataclass
from pathlib import Path


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
    def __init__(self, db_path: Path) -> None:
        self._db_path = db_path

    def is_available(self) -> bool:
        return self._db_path.is_file()

    def lookup_price(
        self,
        *,
        name: str,
        edition: str,
        is_foil: bool = False,
    ) -> CKPriceResult | None:
        if not self.is_available():
            return None
        normalized_name = _normalize(name)
        normalized_edition = _normalize(edition)
        foil_int = 1 if is_foil else 0
        try:
            with sqlite3.connect(self._db_path) as conn:
                row = conn.execute(
                    "SELECT price_retail, qty_retail, price_buy, qty_buying, url"
                    " FROM ck_prices"
                    " WHERE normalized_name = ? AND normalized_edition = ? AND is_foil = ?"
                    " LIMIT 1",
                    (normalized_name, normalized_edition, foil_int),
                ).fetchone()
        except sqlite3.DatabaseError:
            return None
        if row is None:
            return None
        return CKPriceResult(
            price_retail=row[0],
            qty_retail=row[1],
            price_buy=row[2],
            qty_buying=row[3],
            url=row[4],
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
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                normalized_name TEXT NOT NULL,
                edition TEXT NOT NULL,
                normalized_edition TEXT NOT NULL,
                is_foil INTEGER NOT NULL,
                price_retail TEXT,
                qty_retail INTEGER,
                price_buy TEXT,
                qty_buying INTEGER,
                url TEXT
            );

            CREATE INDEX idx_ck_lookup
                ON ck_prices(normalized_name, normalized_edition, is_foil);
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
                " (id, name, normalized_name, edition, normalized_edition,"
                "  is_foil, price_retail, qty_retail, price_buy, qty_buying, url)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    entry.get("id"),
                    name,
                    _normalize(name),
                    edition,
                    _normalize(edition),
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
