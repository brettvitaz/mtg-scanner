"""Anthropic (Claude) LLM Provider implementation."""

import json
import logging
from typing import Any

import httpx

from app.models.recognition import RecognitionResponse, RecognitionResult, RecognitionUploadMetadata
from app.services.errors import RecognitionProviderError
from app.services.llm.base import (
    encode_image_to_data_url,
    extract_anthropic_usage,
    extract_json_from_text,
    parse_recognition_response,
)

logger = logging.getLogger(__name__)


class AnthropicProvider:
    """Anthropic (Claude) LLM provider using Messages API with tool-based structured output."""

    provider_name: str = "anthropic"

    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        base_url: str = "https://api.anthropic.com/v1",
        timeout: float = 30.0,
        response_mode: str = "json_schema",
    ) -> None:
        self.model_name: str | None = model
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout
        self._response_mode = response_mode
        self._schema = self._load_schema()

    def _load_schema(self) -> dict[str, Any]:
        """Load recognition response schema from file."""
        from pathlib import Path

        # Path: services/api/app/services/llm/anthropic_provider.py
        # Need to go up to repo root: 5 levels
        schema_path = (
            Path(__file__).resolve().parents[5]
            / "packages"
            / "schemas"
            / "v1"
            / "llm-output.schema.json"
        )
        return json.loads(schema_path.read_text())

    def recognize(
        self,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
        prompt_text: str,
    ) -> RecognitionResult:
        """Recognize cards in an image using Anthropic Messages API."""
        # For Anthropic, we need base64 data without the data URL prefix
        encoded = encode_image_to_data_url(image_bytes, metadata.content_type)
        # Extract just the base64 part
        base64_data = encoded.split(",")[1]
        media_type = metadata.content_type

        request_body = self._build_request(prompt_text, base64_data, media_type)

        url = f"{self._base_url}/messages"
        logger.info(
            "Calling Anthropic provider: url=%s model=%s mode=%s",
            url,
            self.model_name,
            self._response_mode,
        )

        with httpx.Client(timeout=self._timeout) as client:
            try:
                response = client.post(
                    url,
                    headers={
                        "x-api-key": self._api_key,
                        "anthropic-version": "2023-06-01",
                        "Content-Type": "application/json",
                    },
                    json=request_body,
                )
                response.raise_for_status()
            except httpx.HTTPStatusError as exc:
                body_snippet = getattr(exc.response, "text", "")[:500]
                logger.error(
                    "Anthropic provider HTTP error: status=%d body=%s",
                    exc.response.status_code,
                    body_snippet,
                )
                raise RecognitionProviderError(
                    f"Anthropic recognition request failed: {exc}"
                ) from exc
            except httpx.HTTPError as exc:
                logger.error("Anthropic provider connection error: %s", exc)
                raise RecognitionProviderError(
                    f"Anthropic recognition request failed: {exc}"
                ) from exc

        try:
            payload = response.json()
        except Exception as exc:
            logger.error(
                "Anthropic provider returned non-JSON: content=%s",
                response.text[:500],
            )
            raise RecognitionProviderError(
                f"Anthropic provider returned invalid JSON: {exc}"
            ) from exc

        return RecognitionResult(
            response=self._extract_response(payload),
            usage=extract_anthropic_usage(payload),
        )

    def _build_request(
        self, prompt_text: str, base64_data: str, media_type: str
    ) -> dict[str, Any]:
        """Build Anthropic Messages API request body."""
        body: dict[str, Any] = {
            "model": self.model_name,
            "max_tokens": 4096,
            "system": prompt_text,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "Analyze this Magic: The Gathering card image and extract the card information.",
                        },
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": base64_data,
                            },
                        },
                    ],
                }
            ],
        }

        if self._response_mode == "json_schema":
            # Use tool-based structured output
            body["tools"] = [
                {
                    "name": "card_recognition",
                    "description": "Extract structured information from a Magic: The Gathering card image",
                    "input_schema": self._schema,
                }
            ]
            body["tool_choice"] = {"type": "tool", "name": "card_recognition"}
        elif self._response_mode == "raw":
            # No tools, extract JSON from text response
            pass
        else:
            raise RecognitionProviderError(
                f"Invalid response_mode: {self._response_mode}. "
                "Must be one of: json_schema, raw"
            )

        return body

    def _extract_response(self, payload: dict[str, Any]) -> RecognitionResponse:
        """Extract RecognitionResponse from Anthropic API response."""
        try:
            content = payload.get("content", [])
            if not isinstance(content, list):
                raise RecognitionProviderError(
                    f"Expected content array, got: {type(content)}"
                )
        except Exception as exc:
            raise RecognitionProviderError(
                f"Malformed Anthropic response: {exc}"
            ) from exc

        if self._response_mode == "json_schema":
            # Look for tool_use block
            for block in content:
                if (
                    isinstance(block, dict)
                    and block.get("type") == "tool_use"
                    and block.get("name") == "card_recognition"
                ):
                    input_data = block.get("input")
                    if isinstance(input_data, dict):
                        return RecognitionResponse.model_validate(input_data)
                    elif isinstance(input_data, str):
                        return parse_recognition_response(input_data)

            raise RecognitionProviderError(
                f"No card_recognition tool_use block found in response: {content}"
            )
        else:  # raw mode
            # Look for text block
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    text = block.get("text", "")
                    json_str = extract_json_from_text(text)
                    return parse_recognition_response(json_str)

            raise RecognitionProviderError(
                f"No text block found in response: {content}"
            )
