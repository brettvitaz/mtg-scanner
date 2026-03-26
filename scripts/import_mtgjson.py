#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from app.services.mtgjson_index import import_all_printings


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import MTGJSON AllPrintings.json into the local SQLite index.")
    parser.add_argument("source", type=Path, help="Path to AllPrintings.json")
    parser.add_argument(
        "--db-path",
        type=Path,
        default=Path("services/api/data/mtgjson/mtgjson.sqlite"),
        help="Destination SQLite database path.",
    )
    parser.add_argument(
        "--manifest-path",
        type=Path,
        default=Path("services/api/data/mtgjson/manifest.json"),
        help="Destination manifest path.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = import_all_printings(
        source_path=args.source,
        db_path=args.db_path,
        manifest_path=args.manifest_path,
    )
    print(
        f"Imported {summary.card_count} card printings across {summary.set_count} sets "
        f"(skipped {summary.skipped_card_count})."
    )
    print(f"DB: {args.db_path}")
    print(f"Manifest: {args.manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
