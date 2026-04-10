"""Tests for the pricing_refresh module (fetch, extract, write, refresh)."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest

from app.services.llm.pricing_refresh import (
    PROVIDER_ALLOWLIST,
    RefreshResult,
    extract_prices,
    refresh_prices_from_upstream,
    write_prices,
)

# Upstream fixture with tiered and list-based pricing shapes
UPSTREAM_FIXTURE_TIERED: list[dict[str, Any]] = [
    {
        "id": "openai",
        "name": "OpenAI",
        "models": [
            # Tiered dict prices (base + volume tiers)
            {
                "id": "gpt-5.4",
                "prices": {
                    "input_mtok": {"base": 2.5, "tiers": [{"start": 272000, "price": 5}]},
                    "output_mtok": {"base": 15.0, "tiers": [{"start": 272000, "price": 22.5}]},
                },
            },
            # List of price schedules — prefer entry without constraint
            {
                "id": "o3",
                "prices": [
                    {"constraint": {"start_date": "2025-06-10"}, "prices": {"input_mtok": 2.0, "output_mtok": 8.0}},
                    {"prices": {"input_mtok": 10.0, "output_mtok": 40.0}},
                ],
            },
        ],
    },
]

# Minimal upstream fixture shaped like data_slim.json
UPSTREAM_FIXTURE: list[dict[str, Any]] = [
    {
        "id": "openai",
        "name": "OpenAI",
        "models": [
            {"id": "gpt-4.1-mini", "prices": {"input_mtok": 0.40, "output_mtok": 1.60}},
            {"id": "gpt-4.1", "prices": {"input_mtok": 2.00, "output_mtok": 8.00}},
            # Embedding-only model — should be silently skipped
            {"id": "text-embedding-3-small", "prices": {"tokens_mtok": 0.02}},
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

SMALL_PROVIDERS: frozenset[str] = frozenset({"openai", "moonshotai"})


class TestExtractPrices:
    def test_pulls_all_models_for_allowlisted_providers(self):
        extracted, missing = extract_prices(UPSTREAM_FIXTURE, SMALL_PROVIDERS)
        # All chat-completion models from openai and moonshotai should be present
        assert "gpt-4.1-mini" in extracted
        assert "gpt-4.1" in extracted
        assert "kimi-k2.5" in extracted
        # Anthropic excluded because not in SMALL_PROVIDERS
        assert "claude-sonnet-4-0" not in extracted

    def test_skips_non_allowlisted_providers(self):
        extracted, _ = extract_prices(UPSTREAM_FIXTURE, SMALL_PROVIDERS)
        assert "claude-sonnet-4-0" not in extracted

    def test_skips_models_without_input_output_pricing(self):
        extracted, _ = extract_prices(UPSTREAM_FIXTURE, SMALL_PROVIDERS)
        assert "text-embedding-3-small" not in extracted

    def test_reports_missing_allowlisted_providers(self):
        providers_with_missing = SMALL_PROVIDERS | frozenset({"xai"})
        upstream_without_xai = [p for p in UPSTREAM_FIXTURE if p["id"] != "xai"]
        _, missing = extract_prices(upstream_without_xai, providers_with_missing)
        assert "xai" in missing
        assert "openai" not in missing
        assert "moonshotai" not in missing

    def test_includes_provider_field(self):
        extracted, _ = extract_prices(UPSTREAM_FIXTURE, SMALL_PROVIDERS)
        assert extracted["gpt-4.1-mini"]["provider"] == "openai"
        assert extracted["kimi-k2.5"]["provider"] == "moonshotai"

    def test_correct_price_values(self):
        extracted, _ = extract_prices(UPSTREAM_FIXTURE, SMALL_PROVIDERS)
        assert extracted["gpt-4.1-mini"]["input_mtok"] == 0.40
        assert extracted["gpt-4.1-mini"]["output_mtok"] == 1.60
        assert extracted["kimi-k2.5"]["input_mtok"] == 0.60

    def test_empty_upstream_returns_all_missing(self):
        extracted, missing = extract_prices([], SMALL_PROVIDERS)
        assert extracted == {}
        assert set(missing) == SMALL_PROVIDERS

    def test_missing_providers_sorted(self):
        providers = frozenset({"zz-provider", "aa-provider"})
        _, missing = extract_prices([], providers)
        assert missing == sorted(missing)


class TestExtractPricesTieredShapes:
    """Tests for upstream models with tiered or list-based price structures."""

    def test_tiered_dict_uses_base_price(self):
        extracted, _ = extract_prices(UPSTREAM_FIXTURE_TIERED, frozenset({"openai"}))
        assert "gpt-5.4" in extracted
        assert extracted["gpt-5.4"]["input_mtok"] == 2.5
        assert extracted["gpt-5.4"]["output_mtok"] == 15.0

    def test_list_prices_prefers_unconstrained_entry(self):
        extracted, _ = extract_prices(UPSTREAM_FIXTURE_TIERED, frozenset({"openai"}))
        assert "o3" in extracted
        # The unconstrained entry has input_mtok=10.0; the constrained one has 2.0
        assert extracted["o3"]["input_mtok"] == 10.0
        assert extracted["o3"]["output_mtok"] == 40.0


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
                refresh_prices_from_upstream(path=dest, providers=SMALL_PROVIDERS)
            )

        assert isinstance(result, RefreshResult)
        # gpt-4.1, gpt-4.1-mini, kimi-k2.5 — embedding model skipped
        assert result.model_count == 3
        assert result.missing_providers == []
        assert dest.exists()
        data = json.loads(dest.read_text())
        assert "gpt-4.1-mini" in data["models"]
        assert "kimi-k2.5" in data["models"]
        assert data["models"]["kimi-k2.5"]["input_mtok"] == 0.60

    def test_missing_providers_reported_in_result(self, tmp_path):
        dest = tmp_path / "prices.json"
        providers_with_missing = SMALL_PROVIDERS | frozenset({"xai"})
        with patch(
            "app.services.llm.pricing_refresh.fetch_upstream",
            new=AsyncMock(return_value=UPSTREAM_FIXTURE),
        ):
            result = asyncio.run(
                refresh_prices_from_upstream(path=dest, providers=providers_with_missing)
            )

        assert "xai" in result.missing_providers
        assert result.model_count == 3  # xai has no models, so count unchanged

    def test_raises_on_fetch_failure(self, tmp_path):
        import httpx

        dest = tmp_path / "prices.json"
        with patch(
            "app.services.llm.pricing_refresh.fetch_upstream",
            new=AsyncMock(side_effect=httpx.ConnectError("connection refused")),
        ):
            with pytest.raises(httpx.ConnectError):
                asyncio.run(
                    refresh_prices_from_upstream(path=dest, providers=SMALL_PROVIDERS)
                )

        assert not dest.exists()  # file must not be written on failure

    def test_uses_provider_allowlist_by_default(self, tmp_path):
        dest = tmp_path / "prices.json"
        with patch(
            "app.services.llm.pricing_refresh.fetch_upstream",
            new=AsyncMock(return_value=UPSTREAM_FIXTURE),
        ):
            result = asyncio.run(refresh_prices_from_upstream(path=dest))

        # Default PROVIDER_ALLOWLIST includes anthropic, so claude-sonnet-4-0 should appear
        data = json.loads(dest.read_text())
        assert "claude-sonnet-4-0" in data["models"]
        assert result.missing_providers == []
