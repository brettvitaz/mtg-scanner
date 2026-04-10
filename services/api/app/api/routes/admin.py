"""Admin endpoints — only mounted when MTG_SCANNER_ADMIN_TOKEN is configured."""

from __future__ import annotations

import hmac
import logging

from fastapi import APIRouter, Header, HTTPException, status

from app.services.llm.pricing_refresh import refresh_prices_from_upstream
from app.settings import get_settings

router = APIRouter(tags=["admin"])
logger = logging.getLogger(__name__)


def _verify_admin_token(x_admin_token: str | None) -> None:
    expected = get_settings().mtg_scanner_admin_token or ""
    provided = x_admin_token or ""
    if not expected or not hmac.compare_digest(expected, provided):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid admin token",
        )


@router.post("/admin/pricing/refresh")
async def refresh_pricing(
    x_admin_token: str | None = Header(default=None),
) -> dict[str, object]:
    """Trigger an immediate pricing refresh from upstream.

    Requires the X-Admin-Token header matching MTG_SCANNER_ADMIN_TOKEN.
    Returns 502 on upstream failure; previous pricing data is retained.
    """
    _verify_admin_token(x_admin_token)
    try:
        result = await refresh_prices_from_upstream()
    except Exception as exc:  # noqa: BLE001
        logger.warning("Admin pricing refresh failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Pricing refresh failed; previous data retained.",
        ) from None
    return {
        "source_url": result.source_url,
        "fetched_at": result.fetched_at,
        "model_count": result.model_count,
        "missing_providers": result.missing_providers,
    }
