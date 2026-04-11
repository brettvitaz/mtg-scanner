#!/usr/bin/env python3
"""Download and update LLM model pricing from pydantic/genai-prices."""
from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

from app.services.llm.pricing_refresh import refresh_prices_from_upstream


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Refresh local LLM pricing data from pydantic/genai-prices.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Override the output path (default: services/api/data/pricing/model_prices.json).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        result = asyncio.run(refresh_prices_from_upstream(path=args.output))
    except Exception as exc:  # noqa: BLE001 — CLI; print any error to stderr
        print(f"Pricing refresh failed: {exc}", file=sys.stderr)
        return 1

    print(f"Updated {result.model_count} model(s) at {result.fetched_at}")
    if result.missing_providers:
        print(
            f"Warning: providers not found upstream: {result.missing_providers}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
