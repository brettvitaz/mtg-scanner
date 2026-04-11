"""LLM token pricing data and cost estimation.

Prices are loaded from services/api/data/pricing/model_prices.json, which is
updated by `make api-update-pricing` or the admin pricing refresh endpoint.

The loader uses mtime-based caching so any refresh path (background loop, admin
endpoint, CLI) takes effect on the next call to estimate_cost() without a
restart.

Pricing data sourced from pydantic/genai-prices (MIT):
  https://github.com/pydantic/genai-prices
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

from app.models.recognition import TokenUsage

logger = logging.getLogger(__name__)

PRICING_FILE_PATH: Path = (
    Path(__file__).resolve().parents[3] / "data" / "pricing" / "model_prices.json"
)

_cache: dict[str, tuple[float, float]] = {}
_cache_mtime: float | None = None


def load_prices() -> dict[str, tuple[float, float]]:
    """Return {model_id: (input_usd_per_1m, output_usd_per_1m)}.

    Reads from PRICING_FILE_PATH. Reloads automatically when the file's mtime
    changes (e.g. after a refresh). Returns {} on missing or malformed file.
    """
    global _cache, _cache_mtime
    try:
        mtime = PRICING_FILE_PATH.stat().st_mtime
    except OSError:
        logger.warning("Pricing file not found: %s", PRICING_FILE_PATH)
        return {}
    if _cache_mtime == mtime and _cache:
        return _cache
    try:
        data = json.loads(PRICING_FILE_PATH.read_text(encoding="utf-8"))
        models = data.get("models", {})
        _cache = {
            model_id: (float(entry["input_mtok"]), float(entry["output_mtok"]))
            for model_id, entry in models.items()
        }
        _cache_mtime = mtime
    except (json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
        logger.warning("Pricing file malformed (%s), serving empty prices", exc)
        return {}
    return _cache


def estimate_cost(usage: TokenUsage, model: str | None) -> float | None:
    """Estimate USD cost for a token usage record.

    Returns None if the model is unknown or not provided.
    """
    if model is None:
        return None
    prices = load_prices()
    if model not in prices:
        return None
    input_price, output_price = prices[model]
    return (usage.input_tokens * input_price + usage.output_tokens * output_price) / 1_000_000
