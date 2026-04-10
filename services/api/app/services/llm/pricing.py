"""LLM token pricing data and cost estimation.

Prices are in USD per 1M tokens. Sources checked 2026-04-10:
- OpenAI: https://openai.com/api/pricing/
- Anthropic: https://www.anthropic.com/pricing
- Moonshot: https://platform.moonshot.cn/docs/pricing

Returns None for unknown models rather than raising, so new or custom models
degrade gracefully.
"""

from app.models.recognition import TokenUsage

# {model_name: (input_usd_per_1m, output_usd_per_1m)}
MODEL_PRICES: dict[str, tuple[float, float]] = {
    # OpenAI
    "gpt-4.1": (2.00, 8.00),
    "gpt-4.1-mini": (0.40, 1.60),
    "gpt-4.1-nano": (0.10, 0.40),
    "gpt-4o": (2.50, 10.00),
    "gpt-4o-mini": (0.15, 0.60),
    # Anthropic
    "claude-sonnet-4-0": (3.00, 15.00),
    "claude-haiku-3-5": (0.80, 4.00),
    # Moonshot — verify at https://platform.moonshot.cn/docs/pricing
    "kimi-k2.5": (1.00, 4.00),
}


def estimate_cost(usage: TokenUsage, model: str | None) -> float | None:
    """Estimate USD cost for a token usage record.

    Returns None if the model is unknown or not provided.
    """
    if model is None or model not in MODEL_PRICES:
        return None
    input_price, output_price = MODEL_PRICES[model]
    return (usage.input_tokens * input_price + usage.output_tokens * output_price) / 1_000_000
