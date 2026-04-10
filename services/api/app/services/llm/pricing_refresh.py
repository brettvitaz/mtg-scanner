"""Shared logic for fetching and writing LLM pricing data.

Used by:
- the background refresh loop (pricing_loop.py)
- the admin HTTP endpoint (api/routes/admin.py)
- the CLI script (scripts/update_pricing.py)

Pricing data sourced from pydantic/genai-prices (MIT):
  https://github.com/pydantic/genai-prices
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

from app.services.llm.pricing import PRICING_FILE_PATH

logger = logging.getLogger(__name__)

UPSTREAM_URL = (
    "https://raw.githubusercontent.com/pydantic/genai-prices/main/prices/data_slim.json"
)
FETCH_TIMEOUT = 30.0

# Provider-level allowlist: every model from these providers is imported automatically.
# Adding a new provider here is the only code change needed to expand coverage.
# New models from existing providers flow through on the next daily refresh — no code change.
PROVIDER_ALLOWLIST: frozenset[str] = frozenset({"openai", "anthropic", "moonshotai"})


@dataclass(frozen=True)
class RefreshResult:
    source_url: str
    fetched_at: str
    model_count: int
    missing_providers: list[str] = field(default_factory=list)


async def fetch_upstream(url: str = UPSTREAM_URL) -> list[dict[str, Any]]:
    """Fetch the upstream pricing JSON. Raises httpx.HTTPError on failure."""
    async with httpx.AsyncClient(timeout=FETCH_TIMEOUT, follow_redirects=True) as client:
        response = await client.get(url)
        response.raise_for_status()
        data = response.json()
    if not isinstance(data, list):
        raise ValueError(f"Unexpected upstream response shape: {type(data)}")
    return data


def _resolve_price(value: Any) -> float | None:
    """Resolve a price value that may be a plain number or a tiered dict.

    Upstream uses two shapes:
    - Plain number: {"input_mtok": 2.0}
    - Tiered dict:  {"input_mtok": {"base": 2.0, "tiers": [...]}}

    Returns the base price as a float, or None if the shape is unrecognised.
    """
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, dict):
        base = value.get("base")
        if isinstance(base, (int, float)):
            return float(base)
    return None


def _resolve_prices_dict(raw: Any) -> dict[str, Any] | None:
    """Return a plain prices dict from either a dict or a list of price schedules.

    When prices is a list (tiered/date-constrained schedules), prefer the entry
    without a constraint (the always-applicable base rate).  If all entries have
    constraints, take the first one.
    """
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, list) and raw:
        # Prefer an entry with no constraint (unconditional base rate)
        for entry in raw:
            if isinstance(entry, dict) and "constraint" not in entry:
                return entry.get("prices")
        # Fall back to first entry
        first = raw[0]
        if isinstance(first, dict):
            return first.get("prices")
    return None


def extract_prices(
    upstream: list[dict[str, Any]],
    providers: frozenset[str],
) -> tuple[dict[str, dict[str, Any]], list[str]]:
    """Extract all models from upstream whose provider is in the allowlist.

    Returns (models_dict, missing_providers) where models_dict maps model id
    to {input_mtok, output_mtok, provider}, and missing_providers lists any
    allowlisted providers not found in the upstream data.

    Models without both input_mtok and output_mtok (e.g. embedding-only, image,
    TTS) are skipped silently — they cannot produce a USD cost from a TokenUsage.
    """
    found_providers: set[str] = set()
    extracted: dict[str, dict[str, Any]] = {}
    for provider in upstream:
        provider_id = provider.get("id", "")
        if provider_id not in providers:
            continue
        found_providers.add(provider_id)
        for model in provider.get("models", []):
            model_id = model.get("id", "")
            if not model_id:
                continue
            prices = _resolve_prices_dict(model.get("prices", {}))
            if not isinstance(prices, dict):
                continue
            input_mtok = _resolve_price(prices.get("input_mtok"))
            output_mtok = _resolve_price(prices.get("output_mtok"))
            if input_mtok is None or output_mtok is None:
                continue
            extracted[model_id] = {
                "input_mtok": input_mtok,
                "output_mtok": output_mtok,
                "provider": provider_id,
            }
    missing = sorted(providers - found_providers)
    return extracted, missing


def write_prices(path: Path, data: dict[str, Any]) -> None:
    """Atomically write pricing data to path (tmp file + os.replace)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=path.parent, suffix=".json.tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


async def refresh_prices_from_upstream(
    *,
    path: Path | None = None,
    providers: frozenset[str] | None = None,
) -> RefreshResult:
    """Fetch upstream prices, extract the provider allowlist, and write to path.

    Raises httpx.HTTPError, ValueError, or OSError on failure.
    The caller is responsible for error handling.
    """
    dest = path if path is not None else PRICING_FILE_PATH
    active = providers if providers is not None else PROVIDER_ALLOWLIST

    upstream = await fetch_upstream()
    extracted, missing = extract_prices(upstream, active)
    fetched_at = datetime.now(timezone.utc).isoformat()
    data = {
        "source_url": UPSTREAM_URL,
        "fetched_at": fetched_at,
        "models": extracted,
    }
    write_prices(dest, data)
    logger.info(
        "Pricing file updated: %d models, %d missing providers, path=%s",
        len(extracted),
        len(missing),
        dest,
    )
    return RefreshResult(
        source_url=UPSTREAM_URL,
        fetched_at=fetched_at,
        model_count=len(extracted),
        missing_providers=missing,
    )
