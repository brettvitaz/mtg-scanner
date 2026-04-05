"""Integration tests for LLM providers with mocked HTTP responses."""

import json
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

from app.models.recognition import RecognitionResponse, RecognitionUploadMetadata
from app.services.errors import RecognitionConfigurationError, RecognitionProviderError
from app.services.llm import (
    get_llm_provider,
    OpenAIProvider,
    MoonshotProvider,
    AnthropicProvider,
)
from app.services.llm.base import extract_json_from_text, parse_recognition_response
from app.services.recognizer import MockRecognitionProvider
from app.settings import Settings


@pytest.fixture
def sample_recognition_response():
    """Sample valid recognition response."""
    return {
        "cards": [
            {
                "title": "Lightning Bolt",
                "edition": "Alpha",
                "collector_number": "1",
                "foil": False,
                "confidence": 0.95,
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
            ]
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResponse)
            assert len(result.cards) == 1
            assert result.cards[0].title == "Lightning Bolt"

    def test_recognize_json_mode(
        self, provider, sample_metadata, sample_recognition_response
    ):
        """Test OpenAI provider with json_mode response mode."""
        provider._response_mode = "json_mode"

        mock_response = Mock()
        mock_response.json.return_value = {
            "choices": [
                {"message": {"content": json.dumps(sample_recognition_response)}}
            ]
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResponse)
            assert result.cards[0].title == "Lightning Bolt"

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
            ]
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResponse)
            assert result.cards[0].title == "Lightning Bolt"

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
            ]
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResponse)
            assert result.cards[0].title == "Lightning Bolt"

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
            ]
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResponse)
            assert result.cards[0].title == "Lightning Bolt"

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
            ]
        }
        mock_response.raise_for_status = Mock()

        with patch("httpx.Client.post", return_value=mock_response):
            result = provider.recognize(
                image_bytes=b"fake-image",
                metadata=sample_metadata,
                prompt_text="Extract card info",
            )

            assert isinstance(result, RecognitionResponse)
            assert result.cards[0].title == "Lightning Bolt"

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
            ]
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
            openai_api_key=None,  # Override default
        )
        with pytest.raises(RecognitionConfigurationError) as exc_info:
            get_llm_provider(settings)
        assert "OPENAI_API_KEY" in str(exc_info.value)

    def test_missing_model_raises_error(self):
        """Test error when model is missing."""
        settings = Settings(
            mtg_scanner_llm_provider="openai",
            mtg_scanner_llm_api_key="test-key",
            mtg_scanner_llm_model=None,
            openai_model=None,  # Override default
        )
        with pytest.raises(RecognitionConfigurationError) as exc_info:
            get_llm_provider(settings)
        assert "OPENAI_MODEL" in str(exc_info.value)

    def test_unknown_provider_raises_error(self):
        """Test error for unknown provider."""
        settings = Settings(mtg_scanner_llm_provider="unknown")
        with pytest.raises(RecognitionConfigurationError) as exc_info:
            get_llm_provider(settings)
        assert "Unknown LLM provider" in str(exc_info.value)
