"""Moonshot (Kimi) LLM Provider implementation."""

import json
import logging
from typing import Any

import httpx

from app.models.recognition import RecognitionResponse, RecognitionResult, RecognitionUploadMetadata
from app.services.errors import RecognitionProviderError
from app.services.llm.base import (
    encode_image_to_data_url,
    extract_json_from_text,
    extract_openai_usage,
    parse_recognition_response,
)

logger = logging.getLogger(__name__)


class MoonshotProvider:
    """Moonshot (Kimi) LLM provider using OpenAI-compatible HTTP API.

    Note: Moonshot does not support native json_schema response format.
    It auto-downgrades to json_mode with a warning.
    """

    provider_name: str = "moonshot"

    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        base_url: str = "https://api.moonshot.ai/v1",
        timeout: float = 30.0,
        response_mode: str = "json_mode",
    ) -> None:
        self.model_name: str | None = model
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout

        # Auto-downgrade json_schema to json_mode for Moonshot
        if response_mode == "json_schema":
            logger.warning(
                "Moonshot does not support json_schema. Auto-downgrading to json_mode."
            )
            self._response_mode = "json_mode"
        else:
            self._response_mode = response_mode

        self._schema = self._load_schema()

    def _load_schema(self) -> dict[str, Any]:
        """Load recognition response schema from file."""
        from pathlib import Path

        # Path: services/api/app/services/llm/moonshot_provider.py
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
        """Recognize cards in an image using Moonshot API."""
        data_url = encode_image_to_data_url(image_bytes, metadata.content_type)
        request_body = self._build_request(prompt_text, data_url)

        url = f"{self._base_url}/chat/completions"
        logger.info(
            "Calling Moonshot provider: url=%s model=%s mode=%s",
            url,
            self.model_name,
            self._response_mode,
        )

        with httpx.Client(timeout=self._timeout) as client:
            try:
                response = client.post(
                    url,
                    headers={
                        "Authorization": f"Bearer {self._api_key}",
                        "Content-Type": "application/json",
                    },
                    json=request_body,
                )
                response.raise_for_status()
            except httpx.HTTPStatusError as exc:
                body_snippet = getattr(exc.response, "text", "")[:500]
                logger.error(
                    "Moonshot provider HTTP error: status=%d body=%s",
                    exc.response.status_code,
                    body_snippet,
                )
                raise RecognitionProviderError(
                    f"Moonshot recognition request failed: {exc}"
                ) from exc
            except httpx.HTTPError as exc:
                logger.error("Moonshot provider connection error: %s", exc)
                raise RecognitionProviderError(
                    f"Moonshot recognition request failed: {exc}"
                ) from exc

        try:
            payload = response.json()
        except Exception as exc:
            logger.error(
                "Moonshot provider returned non-JSON: content=%s",
                response.text[:500],
            )
            raise RecognitionProviderError(
                f"Moonshot provider returned invalid JSON: {exc}"
            ) from exc

        return RecognitionResult(
            response=self._extract_response(payload),
            usage=extract_openai_usage(payload),
        )

    def _build_request(self, prompt_text: str, data_url: str) -> dict[str, Any]:
        """Build Moonshot API request body (OpenAI-compatible)."""
        body: dict[str, Any] = {
            "model": self.model_name,
            "messages": [
                {"role": "system", "content": prompt_text},
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "Analyze this Magic: The Gathering card image.",
                        },
                        {"type": "image_url", "image_url": {"url": data_url, "detail": "high"}},
                    ],
                },
            ],
        }

        # Moonshot supports json_mode but not json_schema
        if self._response_mode == "json_mode":
            body["response_format"] = {"type": "json_object"}
        elif self._response_mode == "raw":
            # No response_format, extract JSON from text
            pass
        else:
            raise RecognitionProviderError(
                f"Invalid response_mode: {self._response_mode}. "
                "Must be one of: json_mode, raw"
            )

        return body

    def _extract_response(self, payload: dict[str, Any]) -> RecognitionResponse:
        """Extract RecognitionResponse from Moonshot API response."""
        try:
            choice = payload["choices"][0]
            message = choice["message"]
        except (KeyError, IndexError, TypeError) as exc:
            raise RecognitionProviderError(
                f"Malformed Moonshot response: {exc}"
            ) from exc

        content = message.get("content")
        if not isinstance(content, str):
            raise RecognitionProviderError(
                f"Recognition response did not contain string content: {content}"
            )

        # Parse based on mode
        if self._response_mode == "json_mode":
            return parse_recognition_response(content)
        else:  # raw mode
            json_str = extract_json_from_text(content)
            return parse_recognition_response(json_str)
