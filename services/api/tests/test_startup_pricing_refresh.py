"""Tests for pricing refresh wiring in FastAPI startup/shutdown."""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient


class TestStartupPricingLoop:
    def test_loop_not_started_when_interval_zero(self, monkeypatch):
        """Default config (interval=0) must not spawn a pricing task."""
        monkeypatch.setenv("MTG_SCANNER_PRICING_REFRESH_INTERVAL_HOURS", "0")

        import importlib
        import app.main as main_module

        importlib.reload(main_module)

        with TestClient(main_module.app):
            assert main_module._pricing_task is None

    def test_loop_started_when_interval_positive(self, monkeypatch):
        """interval_hours > 0 must spawn a background asyncio task."""
        monkeypatch.setenv("MTG_SCANNER_PRICING_REFRESH_INTERVAL_HOURS", "24")

        loop_started_with: list[int] = []

        async def fake_loop(interval_hours: int) -> None:
            loop_started_with.append(interval_hours)
            # Block until cancelled so the task stays alive during the test
            await asyncio.sleep(9999)

        import importlib
        import app.main as main_module

        with patch("app.services.llm.pricing_loop.pricing_refresh_loop", new=fake_loop):
            importlib.reload(main_module)
            with TestClient(main_module.app):
                assert main_module._pricing_task is not None

        assert loop_started_with == [24]

    def test_loop_cancelled_on_shutdown(self, monkeypatch):
        """The pricing task must be cancelled cleanly when the app shuts down."""
        monkeypatch.setenv("MTG_SCANNER_PRICING_REFRESH_INTERVAL_HOURS", "24")

        task_cancelled = []

        async def fake_loop(interval_hours: int) -> None:
            try:
                await asyncio.sleep(9999)
            except asyncio.CancelledError:
                task_cancelled.append(True)
                raise

        import importlib
        import app.main as main_module

        with patch("app.services.llm.pricing_loop.pricing_refresh_loop", new=fake_loop):
            importlib.reload(main_module)
            with TestClient(main_module.app):
                pass  # context exit triggers shutdown

        assert task_cancelled == [True]
