"""Tests for the pricing background refresh loop."""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, patch

import pytest

from app.services.llm.pricing_loop import pricing_refresh_loop
from app.services.llm.pricing_refresh import RefreshResult


FAKE_RESULT = RefreshResult(
    source_url="http://example.com",
    fetched_at="2026-01-01T00:00:00+00:00",
    model_count=8,
    missing_providers=[],
)


class TestPricingRefreshLoop:
    def test_runs_immediately_on_first_tick(self):
        """Loop must call refresh before the first sleep."""
        called = []

        async def fake_refresh(**_):
            called.append(True)
            return FAKE_RESULT

        # Use a real (very short) interval; cancel immediately after first refresh.
        async def run():
            with patch(
                "app.services.llm.pricing_loop.refresh_prices_from_upstream",
                new=fake_refresh,
            ):
                task = asyncio.create_task(pricing_refresh_loop(interval_hours=1))
                # Wait long enough for the first refresh but cancel before the sleep completes
                await asyncio.sleep(0.01)
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass

        asyncio.run(run())
        assert called, "refresh must have been called at least once"

    def test_keeps_running_after_failure(self):
        """A failed refresh must not stop the loop."""
        import httpx

        counts = [0]

        async def fake_refresh(**_):
            counts[0] += 1
            if counts[0] == 1:
                raise httpx.ConnectError("connection refused")
            return FAKE_RESULT

        async def run():
            with patch(
                "app.services.llm.pricing_loop.refresh_prices_from_upstream",
                new=fake_refresh,
            ):
                task = asyncio.create_task(pricing_refresh_loop(interval_hours=0))
                # interval_hours=0 → sleep(0) → loop runs continuously; cancel after 2+ calls
                for _ in range(20):
                    await asyncio.sleep(0)
                    if counts[0] >= 2:
                        break
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass

        asyncio.run(run())
        assert counts[0] >= 2

    def test_cancels_cleanly(self):
        async def run():
            with patch(
                "app.services.llm.pricing_loop.refresh_prices_from_upstream",
                new=AsyncMock(return_value=FAKE_RESULT),
            ):
                task = asyncio.create_task(pricing_refresh_loop(interval_hours=0))
                await asyncio.sleep(0)
                task.cancel()
                with pytest.raises(asyncio.CancelledError):
                    await task
                assert task.done()

        asyncio.run(run())
