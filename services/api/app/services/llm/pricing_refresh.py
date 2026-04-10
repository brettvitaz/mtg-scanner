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

# Allowlist: models this project supports.
# {local_model_id: (upstream_provider_id, upstream_model_id)}
MODEL_ALLOWLIST: dict[str, tuple[str, str]] = {
    "gpt-4.1": ("openai", "gpt-4.1"),
    "gpt-4.1-mini": ("openai", "gpt-4.1-mini"),
    "gpt-4.1-nano": ("openai", "gpt-4.1-nano"),
    "gpt-4o": ("openai", "gpt-4o"),
    "gpt-4o-mini": ("openai", "gpt-4o-mini"),
    "claude-sonnet-4-0": ("anthropic", "claude-sonnet-4-0"),
    "claude-haiku-3-5": ("anthropic", "claude-haiku-3-5"),
    "kimi-k2.5": ("moonshotai", "kimi-k2.5"),
}


@dataclass(frozen=True)
class RefreshResult:
    source_url: str
    fetched_at: str
    model_count: int
    missing_models: list[str] = field(default_factory=list)


async def fetch_upstream(url: str = UPSTREAM_URL) -> list[dict[str, Any]]:
    """Fetch the upstream pricing JSON. Raises httpx.HTTPError on failure."""
    async with httpx.AsyncClient(timeout=FETCH_TIMEOUT, follow_redirects=True) as client:
        response = await client.get(url)
        response.raise_for_status()
        data = response.json()
    if not isinstance(data, list):
        raise ValueError(f"Unexpected upstream response shape: {type(data)}")
    return data


def extract_prices(
    upstream: list[dict[str, Any]],
    allowlist: dict[str, tuple[str, str]],
) -> tuple[dict[str, dict[str, Any]], list[str]]:
    """Extract allowlisted model prices from the upstream data.

    Returns (models_dict, missing_model_ids) where models_dict maps local
    model id to {input_mtok, output_mtok, provider} and missing_model_ids
    lists allowlisted models not found in the upstream data.
    """
    # Build a lookup: {(provider_id, model_id): prices_dict}
    upstream_index: dict[tuple[str, str], dict[str, Any]] = {}
    for provider in upstream:
        provider_id = provider.get("id", "")
        for model in provider.get("models", []):
            model_id = model.get("id", "")
            prices = model.get("prices", {})
            if provider_id and model_id and isinstance(prices, dict):
                upstream_index[(provider_id, model_id)] = prices

    extracted: dict[str, dict[str, Any]] = {}
    missing: list[str] = []
    for local_id, (provider_id, upstream_model_id) in allowlist.items():
        prices = upstream_index.get((provider_id, upstream_model_id))
        if prices is None:
            logger.warning(
                "Model %s (%s/%s) not found in upstream pricing data",
                local_id,
                provider_id,
                upstream_model_id,
            )
            missing.append(local_id)
            continue
        input_mtok = prices.get("input_mtok")
        output_mtok = prices.get("output_mtok")
        if input_mtok is None or output_mtok is None:
            logger.warning(
                "Model %s is missing input_mtok or output_mtok in upstream data", local_id
            )
            missing.append(local_id)
            continue
        extracted[local_id] = {
            "input_mtok": float(input_mtok),
            "output_mtok": float(output_mtok),
            "provider": provider_id,
        }
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
    allowlist: dict[str, tuple[str, str]] | None = None,
) -> RefreshResult:
    """Fetch upstream prices, extract the allowlist, and write to path.

    Raises httpx.HTTPError, ValueError, or OSError on failure.
    The caller is responsible for error handling.
    """
    dest = path if path is not None else PRICING_FILE_PATH
    active_allowlist = allowlist if allowlist is not None else MODEL_ALLOWLIST

    upstream = await fetch_upstream()
    extracted, missing = extract_prices(upstream, active_allowlist)
    fetched_at = datetime.now(timezone.utc).isoformat()
    data = {
        "source_url": UPSTREAM_URL,
        "fetched_at": fetched_at,
        "models": extracted,
    }
    write_prices(dest, data)
    logger.info(
        "Pricing file updated: %d models, %d missing, path=%s",
        len(extracted),
        len(missing),
        dest,
    )
    return RefreshResult(
        source_url=UPSTREAM_URL,
        fetched_at=fetched_at,
        model_count=len(extracted),
        missing_models=missing,
    )
