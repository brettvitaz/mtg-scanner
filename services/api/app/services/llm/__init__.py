"""Unified LLM Provider module.

Exports:
    LLMProvider: Protocol for LLM providers
    get_llm_provider: Factory function to create appropriate provider
    OpenAIProvider: OpenAI-compatible provider
    MoonshotProvider: Moonshot (Kimi) provider
    AnthropicProvider: Anthropic (Claude) provider
"""

import logging

from app.services.llm.base import LLMProvider
from app.services.llm.openai_provider import OpenAIProvider
from app.services.llm.moonshot_provider import MoonshotProvider
from app.services.llm.anthropic_provider import AnthropicProvider
from app.services.errors import RecognitionConfigurationError
from app.settings import Settings

logger = logging.getLogger(__name__)

__all__ = [
    "LLMProvider",
    "OpenAIProvider",
    "MoonshotProvider",
    "AnthropicProvider",
    "get_llm_provider",
]


def get_llm_provider(settings: Settings) -> LLMProvider:
    """Factory function to create appropriate LLM provider based on settings.

    Args:
        settings: Application settings

    Returns:
        Configured LLM provider instance

    Raises:
        RecognitionConfigurationError: If provider is unknown or misconfigured
    """
    provider_name = _resolve_provider_name(settings)

    if provider_name == "mock":
        logger.info("Using mock LLM provider")
        from app.services.recognizer import MockRecognitionProvider

        return MockRecognitionProvider()

    if provider_name == "openai":
        return _create_openai_provider(settings)

    if provider_name == "moonshot":
        return _create_moonshot_provider(settings)

    if provider_name == "anthropic":
        return _create_anthropic_provider(settings)

    raise RecognitionConfigurationError(
        f"Unknown LLM provider: '{provider_name}'. "
        "Must be one of: mock, openai, moonshot, anthropic"
    )


def _resolve_provider_name(settings: Settings) -> str:
    """Resolve the active provider from new settings first, then legacy config."""
    llm_provider = (settings.mtg_scanner_llm_provider or "").strip().lower()
    if llm_provider:
        return llm_provider

    legacy_provider = (settings.mtg_scanner_recognizer_provider or "").strip().lower()
    if legacy_provider:
        logger.warning(
            "Using legacy MTG_SCANNER_RECOGNIZER_PROVIDER=%s; prefer MTG_SCANNER_LLM_PROVIDER.",
            legacy_provider,
        )
        return legacy_provider

    return "mock"


def _create_openai_provider(settings: Settings) -> OpenAIProvider:
    """Create OpenAI provider with resolved settings."""
    api_key = settings.openai_api_key or settings.mtg_scanner_llm_api_key
    model = settings.openai_model or settings.mtg_scanner_llm_model or "gpt-4.1-mini"
    base_url = (
        settings.openai_base_url
        or settings.mtg_scanner_llm_base_url
        or "https://api.openai.com/v1"
    )

    if not api_key:
        raise RecognitionConfigurationError(
            "OpenAI provider requires OPENAI_API_KEY or MTG_SCANNER_LLM_API_KEY"
        )

    if not model:
        raise RecognitionConfigurationError(
            "OpenAI provider requires OPENAI_MODEL or MTG_SCANNER_LLM_MODEL"
        )

    logger.info(
        "Using OpenAI provider: model=%s base_url=%s",
        model,
        base_url,
    )

    return OpenAIProvider(
        api_key=api_key,
        model=model,
        base_url=base_url,
        timeout=settings.mtg_scanner_llm_timeout_seconds,
        response_mode=settings.mtg_scanner_llm_response_mode,
        enable_corner_crop=settings.mtg_scanner_enable_corner_crop,
    )


def _create_moonshot_provider(settings: Settings) -> MoonshotProvider:
    """Create Moonshot provider with resolved settings."""
    api_key = settings.moonshot_api_key or settings.mtg_scanner_llm_api_key
    model = settings.moonshot_model or settings.mtg_scanner_llm_model or "kimi-k2.5"
    base_url = (
        settings.moonshot_base_url
        or settings.mtg_scanner_llm_base_url
        or "https://api.moonshot.ai/v1"
    )

    if not api_key:
        raise RecognitionConfigurationError(
            "Moonshot provider requires MOONSHOT_API_KEY or MTG_SCANNER_LLM_API_KEY"
        )

    if not model:
        raise RecognitionConfigurationError(
            "Moonshot provider requires MOONSHOT_MODEL or MTG_SCANNER_LLM_MODEL"
        )

    logger.info(
        "Using Moonshot provider: model=%s base_url=%s",
        model,
        base_url,
    )

    return MoonshotProvider(
        api_key=api_key,
        model=model,
        base_url=base_url,
        timeout=settings.mtg_scanner_llm_timeout_seconds,
        response_mode=settings.mtg_scanner_llm_response_mode,
        enable_corner_crop=settings.mtg_scanner_enable_corner_crop,
    )


def _create_anthropic_provider(settings: Settings) -> AnthropicProvider:
    """Create Anthropic provider with resolved settings."""
    api_key = settings.anthropic_api_key or settings.mtg_scanner_llm_api_key
    model = (
        settings.anthropic_model
        or settings.mtg_scanner_llm_model
        or "claude-sonnet-4-0"
    )
    base_url = (
        settings.anthropic_base_url
        or settings.mtg_scanner_llm_base_url
        or "https://api.anthropic.com/v1"
    )

    if not api_key:
        raise RecognitionConfigurationError(
            "Anthropic provider requires ANTHROPIC_API_KEY or MTG_SCANNER_LLM_API_KEY"
        )

    if not model:
        raise RecognitionConfigurationError(
            "Anthropic provider requires ANTHROPIC_MODEL or MTG_SCANNER_LLM_MODEL"
        )

    logger.info(
        "Using Anthropic provider: model=%s base_url=%s",
        model,
        base_url,
    )

    return AnthropicProvider(
        api_key=api_key,
        model=model,
        base_url=base_url,
        timeout=settings.mtg_scanner_llm_timeout_seconds,
        response_mode=settings.mtg_scanner_llm_response_mode,
        enable_corner_crop=settings.mtg_scanner_enable_corner_crop,
    )
