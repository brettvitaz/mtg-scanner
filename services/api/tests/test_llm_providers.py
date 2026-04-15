"""Integration tests for LLM providers with mocked HTTP responses."""

import json
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

from app.models.recognition import (
    RecognitionResponse,
    RecognitionResult,
    RecognitionUploadMetadata,
    TokenUsage,
    accumulate_usage,
)
from app.services.errors import RecognitionConfigurationError, RecognitionProviderError
from app.services.llm import (
    get_llm_provider,
    OpenAIProvider,
    MoonshotProvider,
    AnthropicProvider,
)
from app.services.llm.base import (
    extract_anthropic_usage,
    extract_json_from_text,
    extract_openai_usage,
    parse_recognition_response,
)
from app.services.recognizer import MockRecognitionProvider
from app.settings import Settings


@pytest.fixture
def sample_recognition_response():
    """Sample valid recognition response including v2 LLM fields."""
    return {
        "cards": [
            {
                "title": "Lightning Bolt",
                "edition": "Alpha",
                "collector_number": "1",
                "foil": False,
                "confidence": 0.95,
                "edition_notes": "LEA set code inferred from black border and art style.",
                "foil_type": "none",
                "foil_evidence": ["no rainbow sheen visible"],
                "list_reprint": "no",
                "list_symbol_visible": False,
                "border_color": "black",
                "copyright_line": "Illus. © Christopher Rush",
                "promo_text": None,
                "set_code": "LEA",
                "rarity": "common",
            }
        ]
    }


@pytest.fixture
def sample_metadata():
    """Sample upload metadata."""
    return RecognitionUploadMetadata(
        filename="test_card.jpg",
        content_type="image/jpeg",
    )


class TestExtractJsonFromText:
    """Tests for JSON extraction utility."""

    def test_extract_plain_json(self):
        """Test extraction from plain JSON."""
        text = '{"cards": [{"title": "Test"}]}'
        result = extract_json_from_text(text)
        assert json.loads(result) == {"cards": [{"title": "Test"}]}

    def test_extract_from_markdown_code_block(self):
        """Test extraction from markdown fenced code block."""
        text = '```json\n{"cards": [{"title": "Test"}]}\n```'
        result = extract_json_from_text(text)
        assert json.loads(result) == {"cards": [{"title": "Test"}]}

    def test_extract_from_markdown_no_language(self):
        """Test extraction from markdown block without language specifier."""
        text = '```\n{"cards": [{"title": "Test"}]}\n```'
        result = extract_json_from_text(text)
        assert json.loads(result) == {"cards": [{"title": "Test"}]}

    def test_extract_from_text_with_prefix(self):
        """Test extraction when JSON is embedded in text."""
        text = 'Here is the result: {"cards": [{"title": "Test"}]} Thank you!'
        result = extract_json_from_text(text)
        assert json.loads(result) == {"cards": [{"title": "Test"}]}

    def test_no_json_object_raises_error(self):
        """Test that error is raised when no JSON object found."""
        text = "This is just plain text with no JSON"
        with pytest.raises(RecognitionProviderError) as exc_info:
            extract_json_from_text(text)
        assert "did not contain a JSON object" in str(exc_info.value)


class TestParseRecognitionResponse:
    """Tests for recognition response parsing."""

    def test_valid_response(self, sample_recognition_response):
        """Test parsing valid recognition response JSON."""
        json_str = json.dumps(sample_recognition_response)
        result = parse_recognition_response(json_str)
        assert isinstance(result, RecognitionResponse)
        assert len(result.cards) == 1
        assert result.cards[0].title == "Lightning Bolt"

    def test_invalid_response_raises_error(self):
        """Test that invalid response raises error."""
        json_str = '{"invalid": "data"}'
        with pytest.raises(RecognitionProviderError):
            parse_recognition_response(json_str)


class TestOpenAIProvider:
    """Tests for OpenAI provider."""

    @pytest.fixture
    def provider(self):
        return OpenAIProvider(
            api_key="test-key",
            model="gpt-4.1-mini",
            base_url="https://api.openai.com/v1",
            timeout=30.0,
            response_mode="json_schema",
        )

    def test_recognize_json_schema_mode(
        self, provider, sample_metadata, sample_recognition_response
    ):
        """Test OpenAI provider with json_schema response mode."""
        mock_response = Mock()
        mock_response.json.return_value = {
            "choices": [
                {"message": {"content": json.dumps(sample_recognition_response)}}
            ],
            "usage": {"prompt_tokens": 1200, "completion_tokens": 400, "total_tokens": 1600},
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResult)
            assert len(result.response.cards) == 1
            assert result.response.cards[0].title == "Lightning Bolt"
            assert result.usage is not None
            assert result.usage.input_tokens == 1200
            assert result.usage.output_tokens == 400
            assert result.usage.total_tokens == 1600

    def test_recognize_json_mode(
        self, provider, sample_metadata, sample_recognition_response
    ):
        """Test OpenAI provider with json_mode response mode."""
        provider._response_mode = "json_mode"

        mock_response = Mock()
        mock_response.json.return_value = {
            "choices": [
                {"message": {"content": json.dumps(sample_recognition_response)}}
            ],
            "usage": {"prompt_tokens": 1000, "completion_tokens": 300, "total_tokens": 1300},
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResult)
            assert result.response.cards[0].title == "Lightning Bolt"
            assert result.usage is not None
            assert result.usage.input_tokens == 1000

    def test_recognize_raw_mode(
        self, provider, sample_metadata, sample_recognition_response
    ):
        """Test OpenAI provider with raw response mode."""
        provider._response_mode = "raw"

        mock_response = Mock()
        mock_response.json.return_value = {
            "choices": [
                {
                    "message": {
                        "content": f"```json\n{json.dumps(sample_recognition_response)}\n```"
                    }
                }
            ],
            "usage": {"prompt_tokens": 900, "completion_tokens": 250, "total_tokens": 1150},
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResult)
            assert result.response.cards[0].title == "Lightning Bolt"
            assert result.usage is not None
            assert result.usage.total_tokens == 1150

    def test_http_error_raises_provider_error(self, provider, sample_metadata):
        """Test that HTTP errors are converted to RecognitionProviderError."""
        import httpx

        mock_response = Mock()
        mock_response.status_code = 401
        mock_response.text = "Unauthorized"
        mock_response.raise_for_status.side_effect = httpx.HTTPStatusError(
            "401 Unauthorized",
            request=Mock(),
            response=mock_response,
        )

        with patch("httpx.Client.post", return_value=mock_response):
            with pytest.raises(RecognitionProviderError) as exc_info:
                provider.recognize(
                    image_bytes=b"fake-image",
                    metadata=sample_metadata,
                    prompt_text="Extract card info",
                )
            assert "failed" in str(exc_info.value).lower()

    def test_malformed_response_raises_error(self, provider, sample_metadata):
        """Test that malformed API response raises error."""
        mock_response = Mock()
        mock_response.json.return_value = {"invalid": "response"}
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            with pytest.raises(RecognitionProviderError):
                provider.recognize(
                    image_bytes=b"fake-image",
                    metadata=sample_metadata,
                    prompt_text="Extract card info",
                )


class TestMoonshotProvider:
    """Tests for Moonshot (Kimi) provider."""

    @pytest.fixture
    def provider(self):
        return MoonshotProvider(
            api_key="test-key",
            model="kimi-k2.5",
            base_url="https://api.moonshot.ai/v1",
            timeout=30.0,
            response_mode="json_mode",
        )

    def test_auto_downgrade_json_schema(self):
        """Test that json_schema auto-downgrades to json_mode."""
        provider = MoonshotProvider(
            api_key="test-key",
            model="kimi-k2.5",
            response_mode="json_schema",  # Should be downgraded
        )
        assert provider._response_mode == "json_mode"

    def test_recognize_json_mode(
        self, provider, sample_metadata, sample_recognition_response
    ):
        """Test Moonshot provider with json_mode."""
        mock_response = Mock()
        mock_response.json.return_value = {
            "choices": [
                {"message": {"content": json.dumps(sample_recognition_response)}}
            ],
            "usage": {"prompt_tokens": 800, "completion_tokens": 200, "total_tokens": 1000},
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResult)
            assert result.response.cards[0].title == "Lightning Bolt"
            assert result.usage is not None
            assert result.usage.input_tokens == 800

    def test_provider_name(self, provider):
        """Test provider name is set correctly."""
        assert provider.provider_name == "moonshot"


class TestAnthropicProvider:
    """Tests for Anthropic (Claude) provider."""

    @pytest.fixture
    def provider(self):
        return AnthropicProvider(
            api_key="test-key",
            model="claude-sonnet-4-0",
            base_url="https://api.anthropic.com/v1",
            timeout=30.0,
            response_mode="json_schema",
        )

    def test_build_request_with_tool(self, provider):
        """Test that request includes tool for structured output."""
        request = provider._build_request(
            prompt_text="Extract cards",
            base64_data="abc123",
            media_type="image/jpeg",
        )

        assert "tools" in request
        assert request["tool_choice"]["type"] == "tool"
        assert request["tool_choice"]["name"] == "card_recognition"
        assert request["tools"][0]["name"] == "card_recognition"

    def test_build_request_raw_mode(self, provider):
        """Test that raw mode doesn't include tools."""
        provider._response_mode = "raw"
        request = provider._build_request(
            prompt_text="Extract cards",
            base64_data="abc123",
            media_type="image/jpeg",
        )

        assert "tools" not in request
        assert "tool_choice" not in request

    def test_recognize_with_tool_use(
        self, provider, sample_metadata, sample_recognition_response
    ):
        """Test recognition with tool_use response."""
        mock_response = Mock()
        mock_response.json.return_value = {
            "content": [
                {
                    "type": "tool_use",
                    "name": "card_recognition",
                    "input": sample_recognition_response,
                }
            ],
            "usage": {"input_tokens": 2000, "output_tokens": 600},
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResult)
            assert result.response.cards[0].title == "Lightning Bolt"
            assert result.usage is not None
            assert result.usage.input_tokens == 2000
            assert result.usage.output_tokens == 600
            assert result.usage.total_tokens == 2600

    def test_recognize_raw_mode(
        self, provider, sample_metadata, sample_recognition_response
    ):
        """Test recognition with raw mode."""
        provider._response_mode = "raw"

        mock_response = Mock()
        mock_response.json.return_value = {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(sample_recognition_response),
                }
            ],
            "usage": {"input_tokens": 1500, "output_tokens": 400},
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResult)
            assert result.response.cards[0].title == "Lightning Bolt"
            assert result.usage is not None
            assert result.usage.total_tokens == 1900

    def test_no_tool_use_block_raises_error(self, provider, sample_metadata):
        """Test error when no tool_use block in response."""
        mock_response = Mock()
        mock_response.json.return_value = {
            "content": [{"type": "text", "text": "Some text"}]
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            with pytest.raises(RecognitionProviderError) as exc_info:
                provider.recognize(
                    image_bytes=b"fake-image",
                    metadata=sample_metadata,
                    prompt_text="Extract card info",
                )
            assert "No card_recognition tool_use block" in str(exc_info.value)

    def test_anthropic_headers(self, provider, sample_metadata):
        """Test that correct headers are sent to Anthropic API."""
        mock_response = Mock()
        mock_response.json.return_value = {
            "content": [
                {
                    "type": "tool_use",
                    "name": "card_recognition",
                    "input": {"cards": []},
                }
            ],
            "usage": {"input_tokens": 100, "output_tokens": 50},
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response) as mock_post:
            provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            call_args = mock_post.call_args
            headers = call_args[1]["headers"]
            assert headers["x-api-key"] == "test-key"
            assert headers["anthropic-version"] == "2023-06-01"


class TestProviderFactory:
    """Tests for provider factory function."""

    def test_get_mock_provider(self):
        """Test factory creates mock provider."""
        settings = Settings(mtg_scanner_llm_provider="mock")
        provider = get_llm_provider(settings)
        assert isinstance(provider, MockRecognitionProvider)
        assert provider.provider_name == "mock"

    def test_get_openai_provider(self):
        """Test factory creates OpenAI provider."""
        settings = Settings(
            mtg_scanner_llm_provider="openai",
            mtg_scanner_llm_api_key="test-key",
            mtg_scanner_llm_model="gpt-4.1-mini",
        )
        provider = get_llm_provider(settings)
        assert isinstance(provider, OpenAIProvider)
        assert provider.provider_name == "openai"
        assert provider.model_name == "gpt-4.1-mini"

    def test_get_openai_provider_with_override(self):
        """Test that provider-specific settings override generic."""
        settings = Settings(
            mtg_scanner_llm_provider="openai",
            openai_api_key="specific-key",
            openai_model="gpt-4o",
            mtg_scanner_llm_api_key="generic-key",
            mtg_scanner_llm_model="gpt-4.1-mini",
        )
        provider = get_llm_provider(settings)
        assert provider.model_name == "gpt-4o"  # Provider-specific wins

    def test_generic_model_applies_to_moonshot_when_no_override(self):
        """Test generic model is used when provider-specific model is unset."""
        settings = Settings(
            mtg_scanner_llm_provider="moonshot",
            mtg_scanner_llm_api_key="test-key",
            mtg_scanner_llm_model="shared-model",
            moonshot_model=None,
        )
        provider = get_llm_provider(settings)
        assert isinstance(provider, MoonshotProvider)
        assert provider.model_name == "shared-model"

    def test_generic_base_url_applies_to_anthropic_when_no_override(self):
        """Test generic base URL is used when provider-specific base URL is unset."""
        settings = Settings(
            mtg_scanner_llm_provider="anthropic",
            mtg_scanner_llm_api_key="test-key",
            mtg_scanner_llm_base_url="https://proxy.example/v1",
            anthropic_base_url=None,
        )
        provider = get_llm_provider(settings)
        assert isinstance(provider, AnthropicProvider)
        assert provider._base_url == "https://proxy.example/v1"

    def test_provider_uses_sensible_default_model(self):
        """Test provider-specific defaults still apply when no model is configured."""
        settings = Settings(
            mtg_scanner_llm_provider="moonshot",
            mtg_scanner_llm_api_key="test-key",
        )
        provider = get_llm_provider(settings)
        assert isinstance(provider, MoonshotProvider)
        assert provider.model_name == "kimi-k2.5"

    def test_legacy_provider_setting_is_used_when_new_setting_unset(self):
        """Test legacy provider selector is still honored as a fallback."""
        settings = Settings(
            mtg_scanner_llm_provider=None,
            mtg_scanner_recognizer_provider="openai",
            mtg_scanner_llm_api_key="test-key",
        )
        provider = get_llm_provider(settings)
        assert isinstance(provider, OpenAIProvider)
        assert provider.provider_name == "openai"

    def test_new_provider_setting_wins_over_legacy_selector(self):
        """Test the new provider selector takes precedence over the legacy setting."""
        settings = Settings(
            mtg_scanner_llm_provider="moonshot",
            mtg_scanner_recognizer_provider="openai",
            mtg_scanner_llm_api_key="test-key",
            moonshot_model=None,
            mtg_scanner_llm_model="shared-model",
        )
        provider = get_llm_provider(settings)
        assert isinstance(provider, MoonshotProvider)
        assert provider.provider_name == "moonshot"
        assert provider.model_name == "shared-model"

    def test_get_moonshot_provider(self):
        """Test factory creates Moonshot provider."""
        settings = Settings(
            mtg_scanner_llm_provider="moonshot",
            mtg_scanner_llm_api_key="test-key",
            mtg_scanner_llm_model="kimi-k2.5",
        )
        provider = get_llm_provider(settings)
        assert isinstance(provider, MoonshotProvider)
        assert provider.provider_name == "moonshot"

    def test_get_anthropic_provider(self):
        """Test factory creates Anthropic provider."""
        settings = Settings(
            mtg_scanner_llm_provider="anthropic",
            mtg_scanner_llm_api_key="test-key",
            mtg_scanner_llm_model="claude-sonnet-4-0",
        )
        provider = get_llm_provider(settings)
        assert isinstance(provider, AnthropicProvider)
        assert provider.provider_name == "anthropic"

    def test_missing_api_key_raises_error(self):
        """Test error when API key is missing."""
        settings = Settings(
            mtg_scanner_llm_provider="openai",
            mtg_scanner_llm_api_key=None,
            openai_api_key=None,
        )
        with pytest.raises(RecognitionConfigurationError) as exc_info:
            get_llm_provider(settings)
        assert "OPENAI_API_KEY" in str(exc_info.value)

    def test_unknown_provider_raises_error(self):
        """Test error for unknown provider."""
        settings = Settings(mtg_scanner_llm_provider="unknown")
        with pytest.raises(RecognitionConfigurationError) as exc_info:
            get_llm_provider(settings)
        assert "Unknown LLM provider" in str(exc_info.value)


class TestAccumulateUsage:
    """Tests for accumulate_usage helper."""

    def test_sums_multiple_usages(self):
        usages = [
            TokenUsage(input_tokens=100, output_tokens=50, total_tokens=150),
            TokenUsage(input_tokens=200, output_tokens=100, total_tokens=300),
        ]
        result = accumulate_usage(usages)
        assert result is not None
        assert result.input_tokens == 300
        assert result.output_tokens == 150
        assert result.total_tokens == 450

    def test_returns_none_for_all_none_inputs(self):
        assert accumulate_usage([None, None]) is None

    def test_skips_none_entries(self):
        usages = [None, TokenUsage(input_tokens=100, output_tokens=50, total_tokens=150), None]
        result = accumulate_usage(usages)
        assert result is not None
        assert result.input_tokens == 100

    def test_returns_none_for_empty_list(self):
        assert accumulate_usage([]) is None


class TestExtractOpenAIUsage:
    """Tests for extract_openai_usage helper."""

    def test_extracts_token_counts(self):
        payload = {"usage": {"prompt_tokens": 1200, "completion_tokens": 400, "total_tokens": 1600}}
        usage = extract_openai_usage(payload)
        assert usage is not None
        assert usage.input_tokens == 1200
        assert usage.output_tokens == 400
        assert usage.total_tokens == 1600

    def test_returns_none_when_no_usage_key(self):
        assert extract_openai_usage({"choices": []}) is None

    def test_returns_none_when_usage_not_dict(self):
        assert extract_openai_usage({"usage": "none"}) is None

    def test_missing_fields_default_to_zero(self):
        usage = extract_openai_usage({"usage": {}})
        assert usage is not None
        assert usage.input_tokens == 0
        assert usage.output_tokens == 0
        assert usage.total_tokens == 0


class TestExtractAnthropicUsage:
    """Tests for extract_anthropic_usage helper."""

    def test_extracts_token_counts(self):
        payload = {"usage": {"input_tokens": 2000, "output_tokens": 600}}
        usage = extract_anthropic_usage(payload)
        assert usage is not None
        assert usage.input_tokens == 2000
        assert usage.output_tokens == 600
        assert usage.total_tokens == 2600

    def test_returns_none_when_no_usage_key(self):
        assert extract_anthropic_usage({"content": []}) is None

    def test_returns_none_when_usage_not_dict(self):
        assert extract_anthropic_usage({"usage": None}) is None

    def test_computes_total_from_input_and_output(self):
        usage = extract_anthropic_usage({"usage": {"input_tokens": 100, "output_tokens": 50}})
        assert usage is not None
        assert usage.total_tokens == 150
