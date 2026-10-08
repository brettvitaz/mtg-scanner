#!/usr/bin/env python3
"""Compare device probe databases with Python references; no network or credentials."""
from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path

from app.services.ck_prices import import_ck_prices


def compare(reference: Path, native: Path, table: str, key: tuple[str, ...]) -> dict[str, object]:
    with sqlite3.connect(f"file:{reference}?mode=ro", uri=True) as old, sqlite3.connect(
        f"file:{native}?mode=ro", uri=True
    ) as new:
        old.row_factory = new.row_factory = sqlite3.Row
        old_cursor = old.execute(f"SELECT * FROM {table}")
        new_cursor = new.execute(f"SELECT * FROM {table}")
        old_columns = {field[0] for field in old_cursor.description}
        new_columns = {field[0] for field in new_cursor.description}
        expected, old_count = keyed_rows(old_cursor, key)
        actual, new_count = keyed_rows(new_cursor, key)
    differences: dict[str, int] = {}
    for identity in expected.keys() & actual.keys():
        for field, value in expected[identity].items():
            other = actual[identity].get(field)
            if field in {"finishes", "color_identity"}:
                value = sorted(str(value).split(",")) if value is not None else None
                other = sorted(str(other).split(",")) if other is not None else None
            elif value is not None and other is not None:
                value, other = str(value), str(other)
            if value != other:
                differences[field] = differences.get(field, 0) + 1
    missing = len(expected.keys() - actual.keys())
    extra = len(actual.keys() - expected.keys())
    schema_matches = old_columns == new_columns
    unique = old_count == len(expected) and new_count == len(actual)
    return {"status": "Pass" if not (missing or extra or differences) and schema_matches and unique else "Fail",
            "referenceCount": old_count, "nativeCount": new_count, "missing": missing, "extra": extra,
            "schemaMatches": schema_matches, "uniqueKeys": unique, "fieldDifferences": differences}


def keyed_rows(cursor: sqlite3.Cursor, key: tuple[str, ...]) -> tuple[dict[tuple[str, ...], dict], int]:
    rows: dict[tuple[str, ...], dict] = {}
    count = 0
    for row in cursor:
        count += 1
        rows[tuple(str(row[field]) for field in key)] = dict(row)
    return rows, count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-catalog", required=True, type=Path)
    parser.add_argument("--native-catalog", required=True, type=Path)
    parser.add_argument("--price-json", required=True, type=Path)
    parser.add_argument("--native-prices", required=True, type=Path)
    parser.add_argument("--reference-prices", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    # Generate a host-only Python price reference from the exact device download.
    payload = json.loads(args.price_json.read_text())
    import_ck_prices(data=payload["data"], db_path=args.reference_prices)
    result = {table: compare(args.reference_catalog, args.native_catalog, table, key)
              for table, key in [("cards", ("uuid",)), ("sets", ("set_code",)),
                                 ("face_names", ("normalized_face_name", "full_card_uuid"))]}
    result["prices"] = compare(args.reference_prices, args.native_prices, "ck_prices", ("id",))
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if any(item["status"] != "Pass" for item in result.values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
