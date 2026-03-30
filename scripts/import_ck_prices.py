#!/usr/bin/env python3
"""Fetch Card Kingdom singles prices and import into local SQLite cache."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import cloudscraper  # type: ignore[import-untyped]

from app.services.ck_prices import import_ck_prices

DEFAULT_URL = "https://www.cardkingdom.com/assets/json/singles_prices.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch and import Card Kingdom singles prices.",
    )
    parser.add_argument(
        "--url",
        default=DEFAULT_URL,
        help="URL of the Card Kingdom singles_prices.json.",
    )
    parser.add_argument(
        "--db-path",
        type=Path,
        default=Path("services/api/data/ck_prices/ck_prices.sqlite"),
        help="Destination SQLite database path.",
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=None,
        help="Use a local JSON file instead of fetching from the URL.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.source:
        print(f"Reading from local file: {args.source}")
        payload = json.loads(args.source.read_text())
    else:
        print(f"Fetching prices from: {args.url}")
        scraper = cloudscraper.create_scraper()
        response = scraper.get(args.url)
        response.raise_for_status()
        payload = response.json()

    data = payload.get("data", [])
    print(f"Found {len(data)} price entries.")

    summary = import_ck_prices(data=data, db_path=args.db_path)
    print(
        f"Imported {summary.total_count} prices"
        f" (skipped {summary.skipped_count})."
    )
    print(f"DB: {args.db_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
