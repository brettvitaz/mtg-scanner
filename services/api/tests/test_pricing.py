"""Tests for LLM pricing loader and cost estimation."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

import pytest

import app.services.llm.pricing as pricing_module
from app.models.recognition import TokenUsage
from app.services.llm.pricing import PRICING_FILE_PATH, estimate_cost, load_prices


@pytest.fixture(autouse=True)
def reset_pricing_cache():
    """Reset the module-level mtime cache between tests."""
    pricing_module._cache = {}
    pricing_module._cache_mtime = None
    yield
    pricing_module._cache = {}
    pricing_module._cache_mtime = None


class TestLoadPrices:
    def test_reads_checked_in_file(self):
        prices = load_prices()
        assert isinstance(prices, dict)
        assert len(prices) > 0
        # kimi-k2.5 corrected value (was a placeholder at 1.00/4.00)
        assert "kimi-k2.5" in prices
        assert prices["kimi-k2.5"] == (0.60, 3.00)

    def test_returns_expected_models(self):
        prices = load_prices()
        for model in ["gpt-4.1-mini", "claude-sonnet-4-0", "kimi-k2.5"]:
            assert model in prices

    def test_missing_file_returns_empty(self, monkeypatch, tmp_path):
        monkeypatch.setattr(pricing_module, "PRICING_FILE_PATH", tmp_path / "nonexistent.json")
        prices = load_prices()
        assert prices == {}

    def test_malformed_file_returns_empty(self, monkeypatch, tmp_path):
        bad_file = tmp_path / "prices.json"
        bad_file.write_text("not valid json", encoding="utf-8")
        monkeypatch.setattr(pricing_module, "PRICING_FILE_PATH", bad_file)
        prices = load_prices()
        assert prices == {}

    def test_reloads_on_mtime_change(self, monkeypatch, tmp_path):
        prices_file = tmp_path / "prices.json"

        def write(data: dict) -> None:
            prices_file.write_text(json.dumps({"models": data}), encoding="utf-8")

        write({"model-a": {"input_mtok": 1.0, "output_mtok": 2.0}})
        # ensure initial mtime is in the past
        past = time.time() - 5
        os.utime(prices_file, (past, past))

        monkeypatch.setattr(pricing_module, "PRICING_FILE_PATH", prices_file)
        first = load_prices()
        assert "model-a" in first

        write({"model-b": {"input_mtok": 3.0, "output_mtok": 6.0}})
        # bump mtime forward so it differs from cached value
        os.utime(prices_file, (past + 2, past + 2))

        second = load_prices()
        assert "model-b" in second
        assert "model-a" not in second

    def test_cache_used_when_mtime_unchanged(self, monkeypatch, tmp_path):
        prices_file = tmp_path / "prices.json"
        prices_file.write_text(
            json.dumps({"models": {"model-x": {"input_mtok": 1.0, "output_mtok": 2.0}}}),
            encoding="utf-8",
        )
        monkeypatch.setattr(pricing_module, "PRICING_FILE_PATH", prices_file)
        first = load_prices()
        # Second call with same mtime must return the exact same dict object (cached)
        second = load_prices()
        assert second is first


class TestEstimateCost:
    def test_known_model_returns_correct_cost(self):
        usage = TokenUsage(input_tokens=1_000_000, output_tokens=0, total_tokens=1_000_000)
        cost = estimate_cost(usage, "gpt-4.1-mini")
        assert cost == 0.40  # $0.40 per 1M input tokens

    def test_output_tokens_priced_separately(self):
        usage = TokenUsage(input_tokens=0, output_tokens=1_000_000, total_tokens=1_000_000)
        cost = estimate_cost(usage, "gpt-4.1-mini")
        assert cost == 1.60  # $1.60 per 1M output tokens

    def test_combined_input_and_output(self):
        # 500k input + 500k output for gpt-4.1-mini: 0.5*0.40 + 0.5*1.60 = 0.20 + 0.80 = 1.00
        usage = TokenUsage(input_tokens=500_000, output_tokens=500_000, total_tokens=1_000_000)
        cost = estimate_cost(usage, "gpt-4.1-mini")
        assert cost == pytest.approx(1.00)

    def test_unknown_model_returns_none(self):
        usage = TokenUsage(input_tokens=1000, output_tokens=200, total_tokens=1200)
        assert estimate_cost(usage, "unknown-model-xyz") is None

    def test_none_model_returns_none(self):
        usage = TokenUsage(input_tokens=1000, output_tokens=200, total_tokens=1200)
        assert estimate_cost(usage, None) is None

    def test_all_known_models_have_valid_prices(self):
        usage = TokenUsage(input_tokens=1000, output_tokens=1000, total_tokens=2000)
        for model in load_prices():
            cost = estimate_cost(usage, model)
            assert cost is not None
            assert cost > 0

    def test_zero_tokens_returns_zero_cost(self):
        usage = TokenUsage(input_tokens=0, output_tokens=0, total_tokens=0)
        cost = estimate_cost(usage, "gpt-4.1-mini")
        assert cost == 0.0
