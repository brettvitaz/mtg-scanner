"""Tests for LLM pricing and cost estimation."""

import pytest

from app.models.recognition import TokenUsage
from app.services.llm.pricing import MODEL_PRICES, estimate_cost


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
        for model in MODEL_PRICES:
            cost = estimate_cost(usage, model)
            assert cost is not None
            assert cost > 0

    def test_zero_tokens_returns_zero_cost(self):
        usage = TokenUsage(input_tokens=0, output_tokens=0, total_tokens=0)
        cost = estimate_cost(usage, "gpt-4.1-mini")
        assert cost == 0.0
