"""Tests for the pricing_refresh module (fetch, extract, write, refresh)."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest

from app.services.llm.pricing_refresh import (
    MODEL_ALLOWLIST,
    RefreshResult,
    extract_prices,
    refresh_prices_from_upstream,
    write_prices,
)

# Minimal upstream fixture shaped like data_slim.json
UPSTREAM_FIXTURE: list[dict[str, Any]] = [
    {
        "id": "openai",
        "name": "OpenAI",
        "models": [
            {"id": "gpt-4.1-mini", "prices": {"input_mtok": 0.40, "output_mtok": 1.60}},
            {"id": "gpt-4.1", "prices": {"input_mtok": 2.00, "output_mtok": 8.00}},
        ],
    },
    {
        "id": "anthropic",
        "name": "Anthropic",
        "models": [
            {"id": "claude-sonnet-4-0", "prices": {"input_mtok": 3.00, "output_mtok": 15.00}},
        ],
    },
    {
        "id": "moonshotai",
        "name": "MoonshotAI",
        "models": [
            {"id": "kimi-k2.5", "prices": {"input_mtok": 0.60, "output_mtok": 3.00}},
        ],
    },
]

SMALL_ALLOWLIST: dict[str, tuple[str, str]] = {
    "gpt-4.1-mini": ("openai", "gpt-4.1-mini"),
    "kimi-k2.5": ("moonshotai", "kimi-k2.5"),
}


class TestExtractPrices:
    def test_pulls_allowlisted_models(self):
        extracted, missing = extract_prices(UPSTREAM_FIXTURE, SMALL_ALLOWLIST)
        assert set(extracted.keys()) == {"gpt-4.1-mini", "kimi-k2.5"}
        assert extracted["gpt-4.1-mini"]["input_mtok"] == 0.40
        assert extracted["gpt-4.1-mini"]["output_mtok"] == 1.60
        assert extracted["kimi-k2.5"]["input_mtok"] == 0.60

    def test_skips_unknown_upstream_models(self):
        upstream_with_extra = UPSTREAM_FIXTURE + [
            {"id": "openai", "name": "OpenAI", "models": [
                {"id": "gpt-99", "prices": {"input_mtok": 100.0, "output_mtok": 200.0}},
            ]},
        ]
        extracted, _ = extract_prices(upstream_with_extra, SMALL_ALLOWLIST)
        assert "gpt-99" not in extracted

    def test_reports_missing_allowlisted_models(self):
        allowlist_with_missing = {
            **SMALL_ALLOWLIST,
            "nonexistent-model": ("openai", "nonexistent-model"),
        }
        extracted, missing = extract_prices(UPSTREAM_FIXTURE, allowlist_with_missing)
        assert "nonexistent-model" in missing
        assert "nonexistent-model" not in extracted

    def test_includes_provider_field(self):
        extracted, _ = extract_prices(UPSTREAM_FIXTURE, SMALL_ALLOWLIST)
        assert extracted["gpt-4.1-mini"]["provider"] == "openai"
        assert extracted["kimi-k2.5"]["provider"] == "moonshotai"

    def test_empty_upstream_returns_all_missing(self):
        extracted, missing = extract_prices([], SMALL_ALLOWLIST)
        assert extracted == {}
        assert set(missing) == set(SMALL_ALLOWLIST.keys())


class TestWritePrices:
    def test_writes_valid_json(self, tmp_path):
        dest = tmp_path / "prices.json"
        data = {"source_url": "http://example.com", "fetched_at": "2026-01-01T00:00:00Z", "models": {}}
        write_prices(dest, data)
        assert dest.exists()
        parsed = json.loads(dest.read_text())
        assert parsed == data

    def test_creates_parent_directories(self, tmp_path):
        dest = tmp_path / "a" / "b" / "prices.json"
        write_prices(dest, {"models": {}})
        assert dest.exists()

    def test_no_temp_file_left_behind(self, tmp_path):
        dest = tmp_path / "prices.json"
        write_prices(dest, {"models": {}})
        leftover = list(tmp_path.glob("*.tmp"))
        assert leftover == []

    def test_overwrites_existing_file(self, tmp_path):
        dest = tmp_path / "prices.json"
        dest.write_text('{"models": {"old": {}}}')
        write_prices(dest, {"models": {"new": {}}})
        parsed = json.loads(dest.read_text())
        assert "new" in parsed["models"]
        assert "old" not in parsed["models"]


class TestRefreshPricesFromUpstream:
    def test_end_to_end_with_stubbed_fetch(self, tmp_path):
        dest = tmp_path / "prices.json"
        with patch(
            "app.services.llm.pricing_refresh.fetch_upstream",
            new=AsyncMock(return_value=UPSTREAM_FIXTURE),
        ):
            result = asyncio.run(
                refresh_prices_from_upstream(path=dest, allowlist=SMALL_ALLOWLIST)
            )

        assert isinstance(result, RefreshResult)
        assert result.model_count == 2
        assert result.missing_models == []
        assert dest.exists()
        data = json.loads(dest.read_text())
        assert "gpt-4.1-mini" in data["models"]
        assert "kimi-k2.5" in data["models"]
        assert data["models"]["kimi-k2.5"]["input_mtok"] == 0.60

    def test_reports_missing_models_in_result(self, tmp_path):
        dest = tmp_path / "prices.json"
        allowlist_with_missing = {
            **SMALL_ALLOWLIST,
            "ghost-model": ("openai", "ghost-model"),
        }
        with patch(
            "app.services.llm.pricing_refresh.fetch_upstream",
            new=AsyncMock(return_value=UPSTREAM_FIXTURE),
        ):
            result = asyncio.run(
                refresh_prices_from_upstream(path=dest, allowlist=allowlist_with_missing)
            )

        assert "ghost-model" in result.missing_models
        assert result.model_count == 2  # only the two that were found

    def test_raises_on_fetch_failure(self, tmp_path):
        import httpx

        dest = tmp_path / "prices.json"
        with patch(
            "app.services.llm.pricing_refresh.fetch_upstream",
            new=AsyncMock(side_effect=httpx.ConnectError("connection refused")),
        ):
            with pytest.raises(httpx.ConnectError):
                asyncio.run(
                    refresh_prices_from_upstream(path=dest, allowlist=SMALL_ALLOWLIST)
                )

        assert not dest.exists()  # file must not be written on failure
