from __future__ import annotations

import json
import re
import sqlite3
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SPLIT_LAYOUTS = {"split", "aftermath", "fuse"}

SPACE_PUNCTUATION = {
    "-",
    "‐",
    "‑",
    "‒",
    "–",
    "—",
    "−",
    "•",
    ":",
    ",",
    ".",
    "/",
}
DROP_PUNCTUATION = {
    "'",
    "\u2018",
    "\u2019",
    "\u00b4",
    "`",
    '"',
    "\u201c",
    "\u201d",
}
NON_ALNUM_WHITESPACE_RE = re.compile(r"[^0-9a-z\s]+")

_CARD_COLUMNS = (
    "uuid, name, normalized_name, set_code, set_name, collector_number,"
    " normalized_collector_number, language, layout, release_date, is_promo,"
    " rarity, type_line, oracle_text, mana_cost, power, toughness, loyalty, defense,"
    " scryfall_id, card_kingdom_url, card_kingdom_foil_url, finishes, color_identity"
)


@dataclass(frozen=True, slots=True)
class CardRecord:
    uuid: str
    name: str
    normalized_name: str
    set_code: str
    set_name: str | None
    collector_number: str | None
    normalized_collector_number: str | None
    language: str | None
    layout: str | None
    release_date: str | None
    is_promo: bool | None
    rarity: str | None = None
    type_line: str | None = None
    oracle_text: str | None = None
    mana_cost: str | None = None
    power: str | None = None
    toughness: str | None = None
    loyalty: str | None = None
    defense: str | None = None
    scryfall_id: str | None = None
    card_kingdom_url: str | None = None
    card_kingdom_foil_url: str | None = None
    finishes: str | None = None
    color_identity: str | None = None

    @property
    def has_foil(self) -> bool:
        return "foil" in (self.finishes or "").split(",")

    @property
    def has_non_foil(self) -> bool:
        return "nonfoil" in (self.finishes or "").split(",")

    @property
    def has_etched(self) -> bool:
        return "etched" in (self.finishes or "").split(",")


@dataclass(frozen=True, slots=True)
class SetRecord:
    set_code: str
    set_name: str
    normalized_set_name: str
    release_date: str | None


@dataclass(frozen=True, slots=True)
class ImportSummary:
    set_count: int
    card_count: int
    skipped_card_count: int


class MTGJSONImportError(RuntimeError):
    pass


class MTGJSONIndex:
    def __init__(self, db_path: Path) -> None:
        self._db_path = db_path

    @property
    def db_path(self) -> Path:
        return self._db_path

    def is_available(self) -> bool:
        return self._db_path.is_file()

    def lookup_exact(
        self,
        *,
        title: str,
        set_code: str,
        collector_number: str,
    ) -> CardRecord | None:
        rows = self._fetch_cards(
            f"""
            SELECT {_CARD_COLUMNS}
            FROM cards
            WHERE normalized_name = ?
              AND set_code = ?
              AND normalized_collector_number = ?
            LIMIT 2
            """,
            (normalize_title(title), normalize_set_code(set_code), normalize_collector_number(collector_number)),
        )
        if len(rows) == 1:
            return rows[0]
        return None

    def lookup_by_name_and_set(self, *, title: str, set_code: str) -> list[CardRecord]:
        return self._fetch_cards(
            f"""
            SELECT {_CARD_COLUMNS}
            FROM cards
            WHERE normalized_name = ?
              AND set_code = ?
            ORDER BY release_date DESC, collector_number ASC
            """,
            (normalize_title(title), normalize_set_code(set_code)),
        )

    def lookup_by_name_and_number(
        self,
        *,
        title: str,
        collector_number: str,
    ) -> list[CardRecord]:
        return self._fetch_cards(
            f"""
            SELECT {_CARD_COLUMNS}
            FROM cards
            WHERE normalized_name = ?
              AND normalized_collector_number = ?
            ORDER BY release_date DESC, set_code ASC
            """,
            (normalize_title(title), normalize_collector_number(collector_number)),
        )

    def lookup_by_face_name(self, *, title: str) -> list[CardRecord]:
        """Look up cards where title matches an individual face of a split card.

        Returns an empty list if the face_names table does not exist (old database).
        """
        if not self.is_available():
            return []
        with sqlite3.connect(self._db_path) as conn:
            table_exists = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='face_names'"
            ).fetchone()
        if not table_exists:
            return []
        return self._fetch_cards(
            f"""
            SELECT {_CARD_COLUMNS}
            FROM cards
            WHERE uuid IN (
                SELECT full_card_uuid FROM face_names
                WHERE normalized_face_name = ?
            )
            ORDER BY release_date DESC, set_code ASC
            """,
            (normalize_title(title),),
        )

    def lookup_all_printings_by_name(self, *, title: str) -> list[CardRecord]:
        return self._fetch_cards(
            f"""
            SELECT {_CARD_COLUMNS}
            FROM cards
            WHERE normalized_name = ?
            ORDER BY release_date DESC, set_code ASC, collector_number ASC
            """,
            (normalize_title(title),),
        )

    def resolve_set(self, edition_text: str) -> str | None:
        normalized_code = normalize_set_code(edition_text)
        if not normalized_code:
            return None

        row = self._fetch_one(
            "SELECT set_code FROM sets WHERE set_code = ?",
            (normalized_code,),
        )
        if row is not None:
            return str(row[0])

        normalized_name = normalize_set_name(edition_text)
        if not normalized_name:
            return None

        row = self._fetch_one(
            "SELECT set_code FROM sets WHERE normalized_set_name = ?",
            (normalized_name,),
        )
        if row is not None:
            return str(row[0])
        return None

    def search_candidates(
        self,
        *,
        title: str,
        set_code: str | None = None,
        collector_number: str | None = None,
        limit: int = 10,
    ) -> list[CardRecord]:
        query = [
            f"""
            SELECT {_CARD_COLUMNS}
            FROM cards
            WHERE normalized_name = ?
            """
        ]
        params: list[Any] = [normalize_title(title)]

        if set_code:
            query.append("AND set_code = ?")
            params.append(normalize_set_code(set_code))
        if collector_number:
            query.append("AND normalized_collector_number = ?")
            params.append(normalize_collector_number(collector_number))

        query.append("ORDER BY release_date DESC, set_code ASC, collector_number ASC LIMIT ?")
        params.append(limit)
        return self._fetch_cards("\n".join(query), tuple(params))

    def search_names_by_prefix(self, *, query: str, limit: int = 20) -> list[str]:
        """Return distinct card names matching the query.

        Single token: prefix match (uses index).
        Multiple tokens: each token must appear as a substring in the normalized name.
        """
        normalized = normalize_title(query)
        if not normalized or not self.is_available():
            return []
        tokens = normalized.split()
        if not tokens:
            return []
        if len(tokens) == 1:
            sql = "SELECT DISTINCT name FROM cards WHERE normalized_name LIKE ? ORDER BY name LIMIT ?"
            params: tuple = (tokens[0] + "%", limit)
        else:
            conditions = " AND ".join("normalized_name LIKE ?" for _ in tokens)
            # Sort: names starting with the first token appear before mid-word matches.
            sql = (
                f"SELECT DISTINCT name FROM cards WHERE {conditions}"
                " ORDER BY CASE WHEN normalized_name LIKE ? THEN 0 ELSE 1 END, name LIMIT ?"
            )
            params = tuple(f"%{token}%" for token in tokens) + (tokens[0] + "%", limit)
        with sqlite3.connect(self._db_path) as conn:
            rows = conn.execute(sql, params).fetchall()
        return [row[0] for row in rows]

    def lookup_by_set_and_number(
        self,
        *,
        set_code: str,
        collector_number: str,
    ) -> CardRecord | None:
        """Return a card matching set_code and collector_number, or None if not found.

        Uses the idx_cards_set_number index for efficient lookup without requiring a card name.
        Intended for future CSV/JSON import where rows may carry set+number but not the card name.
        """
        rows = self._fetch_cards(
            f"""
            SELECT {_CARD_COLUMNS}
            FROM cards
            WHERE set_code = ?
              AND normalized_collector_number = ?
            LIMIT 2
            """,
            (normalize_set_code(set_code), normalize_collector_number(collector_number)),
        )
        if len(rows) == 1:
            return rows[0]
        return None

    def check_list_reprint(self, *, set_code: str, collector_number: str) -> CardRecord | None:
        """Check if a card identified by set_code and collector_number exists in a List set.

        PLST uses compound collector numbers like "C16-78" (original_set-original_number).
        MB1 and MB2 use the original collector number directly.

        Returns the matching List CardRecord ("PLST", "MB1", or "MB2") if found, else None.
        """
        plst_number = f"{set_code}-{collector_number}"
        plst_record = self.lookup_by_set_and_number(set_code="PLST", collector_number=plst_number)
        if plst_record is not None:
            return plst_record
        mb1_record = self.lookup_by_set_and_number(set_code="MB1", collector_number=collector_number)
        if mb1_record is not None:
            return mb1_record
        mb2_record = self.lookup_by_set_and_number(set_code="MB2", collector_number=collector_number)
        if mb2_record is not None:
            return mb2_record
        return None

    def _fetch_cards(self, sql: str, params: tuple[Any, ...]) -> list[CardRecord]:
        if not self.is_available():
            return []
        with sqlite3.connect(self._db_path) as conn:
            rows = conn.execute(sql, params).fetchall()
        return [
            CardRecord(
                uuid=row[0],
                name=row[1],
                normalized_name=row[2],
                set_code=row[3],
                set_name=row[4],
                collector_number=row[5],
                normalized_collector_number=row[6],
                language=row[7],
                layout=row[8],
                release_date=row[9],
                is_promo=bool(row[10]) if row[10] is not None else None,
                rarity=row[11],
                type_line=row[12],
                oracle_text=row[13],
                mana_cost=row[14],
                power=row[15],
                toughness=row[16],
                loyalty=row[17],
                defense=row[18],
                scryfall_id=row[19],
                card_kingdom_url=row[20],
                card_kingdom_foil_url=row[21],
                finishes=row[22] if len(row) > 22 else None,
                color_identity=row[23] if len(row) > 23 else None,
            )
            for row in rows
        ]

    def _fetch_one(self, sql: str, params: tuple[Any, ...]) -> tuple[Any, ...] | None:
        if not self.is_available():
            return None
        with sqlite3.connect(self._db_path) as conn:
            return conn.execute(sql, params).fetchone()


def normalize_title(value: str | None) -> str:
    if not value:
        return ""

    normalized = unicodedata.normalize("NFKC", value).lower().strip()
    chars: list[str] = []
    for char in normalized:
        if char in DROP_PUNCTUATION:
            continue
        if char in SPACE_PUNCTUATION:
            chars.append(" ")
            continue
        chars.append(char)

    text = "".join(chars)
    text = NON_ALNUM_WHITESPACE_RE.sub(" ", text)
    return " ".join(text.split())


def normalize_set_name(value: str | None) -> str:
    return normalize_title(value)


def normalize_set_code(value: str | None) -> str:
    if not value:
        return ""
    return unicodedata.normalize("NFKC", value).strip().upper()


def normalize_collector_number(value: str | None) -> str:
    if not value:
        return ""
    text = unicodedata.normalize("NFKC", value).strip().lower().replace(" ", "")
    if not text:
        return ""
    prefix_chars: list[str] = []
    suffix_chars: list[str] = []
    seen_non_digit = False
    for char in text:
        if char.isdigit() and not seen_non_digit:
            prefix_chars.append(char)
        elif char.isalnum():
            seen_non_digit = True
            suffix_chars.append(char)
    if not prefix_chars and not suffix_chars:
        return ""
    digits = "".join(prefix_chars).lstrip("0") or ("0" if prefix_chars else "")
    return f"{digits}{''.join(suffix_chars)}"


def create_schema(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db_path) as conn:
        conn.executescript(
            """
            DROP TABLE IF EXISTS cards;
            DROP TABLE IF EXISTS sets;

            CREATE TABLE sets (
                set_code TEXT PRIMARY KEY,
                set_name TEXT NOT NULL,
                normalized_set_name TEXT NOT NULL,
                release_date TEXT NULL,
                keyrune_code TEXT NULL
            );

            CREATE TABLE cards (
                uuid TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                ascii_name TEXT NULL,
                normalized_name TEXT NOT NULL,
                set_code TEXT NOT NULL,
                set_name TEXT NULL,
                collector_number TEXT NULL,
                normalized_collector_number TEXT NULL,
                language TEXT NULL,
                layout TEXT NULL,
                release_date TEXT NULL,
                is_promo INTEGER NULL,
                rarity TEXT NULL,
                type_line TEXT NULL,
                oracle_text TEXT NULL,
                mana_cost TEXT NULL,
                power TEXT NULL,
                toughness TEXT NULL,
                loyalty TEXT NULL,
                defense TEXT NULL,
                scryfall_id TEXT NULL,
                card_kingdom_url TEXT NULL,
                card_kingdom_foil_url TEXT NULL,
                finishes TEXT NULL,
                color_identity TEXT NULL
            );

            CREATE INDEX idx_cards_name ON cards(normalized_name);
            CREATE INDEX idx_cards_name_set ON cards(normalized_name, set_code);
            CREATE INDEX idx_cards_name_set_number ON cards(normalized_name, set_code, normalized_collector_number);
            CREATE INDEX idx_cards_set_number ON cards(set_code, normalized_collector_number);
            CREATE INDEX idx_sets_name ON sets(normalized_set_name);

            DROP TABLE IF EXISTS face_names;
            CREATE TABLE face_names (
                face_name TEXT NOT NULL,
                normalized_face_name TEXT NOT NULL,
                full_card_uuid TEXT NOT NULL,
                UNIQUE(normalized_face_name, full_card_uuid)
            );
            CREATE INDEX idx_face_names ON face_names(normalized_face_name);
            """
        )


def import_all_printings(*, source_path: Path, db_path: Path, manifest_path: Path) -> ImportSummary:
    try:
        payload = json.loads(source_path.read_text())
    except json.JSONDecodeError as exc:
        raise MTGJSONImportError(f"Malformed MTGJSON source file: {source_path}") from exc

    if not isinstance(payload, dict) or "data" not in payload or not isinstance(payload["data"], dict):
        raise MTGJSONImportError("MTGJSON source must contain a top-level 'data' object.")

    create_schema(db_path)

    set_count = 0
    card_count = 0
    skipped_card_count = 0

    with sqlite3.connect(db_path) as conn:
        for set_code, set_payload in payload["data"].items():
            if not isinstance(set_payload, dict):
                continue
            canonical_set_code = normalize_set_code(set_payload.get("code") or set_code)
            set_name = set_payload.get("name")
            if not canonical_set_code or not set_name:
                continue

            set_count += 1
            conn.execute(
                "INSERT INTO sets (set_code, set_name, normalized_set_name, release_date, keyrune_code)"
                " VALUES (?, ?, ?, ?, ?)",
                (
                    canonical_set_code,
                    set_name,
                    normalize_set_name(set_name),
                    set_payload.get("releaseDate"),
                    set_payload.get("keyruneCode"),
                ),
            )

            seen_in_set: set[tuple[str, str]] = set()
            for card in set_payload.get("cards", []):
                if not isinstance(card, dict):
                    skipped_card_count += 1
                    continue
                uuid = card.get("uuid")
                name = card.get("name")
                if not uuid or not name:
                    skipped_card_count += 1
                    continue
                collector_number = card.get("number")
                dedup_key = (normalize_title(card.get("asciiName") or name), normalize_collector_number(collector_number))
                if dedup_key in seen_in_set:
                    # Second face of a split card — merge per-face fields into the existing row
                    face_type = card.get("type")
                    face_text = card.get("text")
                    face_mana = card.get("manaCost")
                    if face_type or face_text or face_mana:
                        conn.execute(
                            """
                            UPDATE cards SET
                                type_line = CASE WHEN type_line IS NOT NULL AND ? IS NOT NULL
                                                 THEN type_line || ' // ' || ?
                                                 ELSE COALESCE(type_line, ?) END,
                                oracle_text = CASE WHEN oracle_text IS NOT NULL AND ? IS NOT NULL
                                                   THEN oracle_text || '\n---\n' || ?
                                                   ELSE COALESCE(oracle_text, ?) END,
                                mana_cost = CASE WHEN mana_cost IS NOT NULL AND ? IS NOT NULL
                                                 THEN mana_cost || ' // ' || ?
                                                 ELSE COALESCE(mana_cost, ?) END
                            WHERE normalized_name = ? AND set_code = ?
                              AND normalized_collector_number = ?
                            """,
                            (
                                face_type, face_type, face_type,
                                face_text, face_text, face_text,
                                face_mana, face_mana, face_mana,
                                normalize_title(card.get("asciiName") or name),
                                canonical_set_code,
                                normalize_collector_number(collector_number),
                            ),
                        )
                    skipped_card_count += 1
                    continue
                seen_in_set.add(dedup_key)
                identifiers = card.get("identifiers") or {}
                purchase_urls = card.get("purchaseUrls") or {}
                finishes_list: list[str] = card.get("finishes") or []
                finishes_str = ",".join(finishes_list) if finishes_list else None
                color_identity_list: list[str] = card.get("colorIdentity") or []
                color_identity_str = ",".join(color_identity_list) if color_identity_list else None
                conn.execute(
                    """
                    INSERT INTO cards (
                        uuid, name, ascii_name, normalized_name, set_code, set_name,
                        collector_number, normalized_collector_number, language, layout,
                        release_date, is_promo, rarity, type_line, oracle_text,
                        mana_cost, power, toughness, loyalty, defense, scryfall_id,
                        card_kingdom_url, card_kingdom_foil_url, finishes, color_identity
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        uuid,
                        name,
                        card.get("asciiName"),
                        normalize_title(card.get("asciiName") or name),
                        canonical_set_code,
                        set_name,
                        collector_number,
                        normalize_collector_number(collector_number),
                        card.get("language"),
                        card.get("layout"),
                        set_payload.get("releaseDate"),
                        _normalize_bool(card.get("isPromo")),
                        card.get("rarity"),
                        card.get("type"),
                        card.get("text"),
                        card.get("manaCost"),
                        card.get("power"),
                        card.get("toughness"),
                        card.get("loyalty"),
                        card.get("defense"),
                        identifiers.get("scryfallId"),
                        purchase_urls.get("cardKingdom"),
                        purchase_urls.get("cardKingdomFoil"),
                        finishes_str,
                        color_identity_str,
                    ),
                )
                card_count += 1

                if card.get("layout") in SPLIT_LAYOUTS and " // " in name:
                    for face in name.split(" // "):
                        face_stripped = face.strip()
                        if face_stripped:
                            conn.execute(
                                "INSERT OR IGNORE INTO face_names "
                                "(face_name, normalized_face_name, full_card_uuid) "
                                "VALUES (?, ?, ?)",
                                (face_stripped, normalize_title(face_stripped), uuid),
                            )

        conn.commit()

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "source_path": str(source_path),
        "imported_at": __import__("datetime").datetime.now(__import__("datetime").UTC).isoformat(),
        "mtgjson_version": payload.get("meta", {}).get("version"),
        "mtgjson_date": payload.get("meta", {}).get("date"),
        "total_set_count": set_count,
        "total_card_printing_count": card_count,
        "skipped_card_count": skipped_card_count,
        "importer_version": 3,
        "db_path": str(db_path),
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return ImportSummary(set_count=set_count, card_count=card_count, skipped_card_count=skipped_card_count)


def _normalize_bool(value: Any) -> int | None:
    if value is None:
        return None
    return 1 if bool(value) else 0
