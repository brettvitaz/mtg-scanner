"""Background asyncio task for periodic LLM pricing refresh."""

from __future__ import annotations

import asyncio
import logging

from app.services.llm.pricing_refresh import refresh_prices_from_upstream

logger = logging.getLogger(__name__)


async def pricing_refresh_loop(interval_hours: int) -> None:
    """Refresh prices immediately, then every interval_hours until cancelled."""
    while True:
        try:
            result = await refresh_prices_from_upstream()
            logger.info(
                "Pricing refresh: ok, models=%d, missing_providers=%s",
                result.model_count,
                result.missing_providers or "none",
            )
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 — loop must never die on transient error
            logger.warning("Pricing refresh failed (will retry next interval): %s", exc)
        await asyncio.sleep(interval_hours * 3600)
