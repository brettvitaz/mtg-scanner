"""OpenAI LLM Provider implementation."""

import json
import logging
from typing import Any

import httpx

from app.models.recognition import RecognitionResponse, RecognitionResult, RecognitionUploadMetadata
from app.services.errors import RecognitionProviderError
from app.services.llm.base import (
    CORNER_CROP_ABSENT_TEXT,
    CORNER_CROP_PRESENT_TEXT,
    encode_image_to_data_url,
    extract_json_from_text,
    extract_openai_usage,
    maybe_corner_crop,
    parse_recognition_response,
)

logger = logging.getLogger(__name__)


class OpenAIProvider:
    """OpenAI-compatible LLM provider using HTTP API."""

    provider_name: str = "openai"

    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        base_url: str = "https://api.openai.com/v1",
        timeout: float = 30.0,
        response_mode: str = "json_schema",
        enable_corner_crop: bool = True,
    ) -> None:
        self.model_name: str | None = model
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout
        self._response_mode = response_mode
        self._enable_corner_crop = enable_corner_crop
        self._schema = self._load_schema()

    def _load_schema(self) -> dict[str, Any]:
        """Load recognition response schema from file."""
        from pathlib import Path

        # Path: services/api/app/services/llm/openai_provider.py
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
        """Recognize cards in an image using OpenAI API."""
        data_url = encode_image_to_data_url(image_bytes, metadata.content_type)
        corner_bytes = maybe_corner_crop(image_bytes, self._enable_corner_crop)
        corner_url = encode_image_to_data_url(corner_bytes, "image/jpeg") if corner_bytes else None
        request_body = self._build_request(prompt_text, data_url, corner_url)

        url = f"{self._base_url}/chat/completions"
        logger.info(
            "Calling OpenAI provider: url=%s model=%s mode=%s",
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
                    "OpenAI provider HTTP error: status=%d body=%s",
                    exc.response.status_code,
                    body_snippet,
                )
                raise RecognitionProviderError(
                    f"OpenAI recognition request failed: {exc}"
                ) from exc
            except httpx.HTTPError as exc:
                logger.error("OpenAI provider connection error: %s", exc)
                raise RecognitionProviderError(
                    f"OpenAI recognition request failed: {exc}"
                ) from exc

        try:
            payload = response.json()
        except Exception as exc:
            logger.error(
                "OpenAI provider returned non-JSON: content=%s",
                response.text[:500],
            )
            raise RecognitionProviderError(
                f"OpenAI provider returned invalid JSON: {exc}"
            ) from exc

        return RecognitionResult(
            response=self._extract_response(payload),
            usage=extract_openai_usage(payload),
        )

    def _build_request(
        self, prompt_text: str, data_url: str, corner_url: str | None = None
    ) -> dict[str, Any]:
        """Build OpenAI API request body."""
        user_content: list[dict[str, Any]] = [
            {
                "type": "text",
                "text": "Analyze this Magic: The Gathering card image.",
            },
            {"type": "image_url", "image_url": {"url": data_url, "detail": "high"}},
        ]
        if corner_url:
            user_content.extend([
                {"type": "text", "text": CORNER_CROP_PRESENT_TEXT},
                {"type": "image_url", "image_url": {"url": corner_url, "detail": "high"}},
            ])
        else:
            user_content.append({"type": "text", "text": CORNER_CROP_ABSENT_TEXT})

        body: dict[str, Any] = {
            "model": self.model_name,
            "messages": [
                {"role": "system", "content": prompt_text},
                {"role": "user", "content": user_content},
            ],
        }

        if self._response_mode == "json_schema":
            body["response_format"] = {
                "type": "json_schema",
                "json_schema": {
                    "name": "recognition_response",
                    "schema": self._schema,
                },
            }
        elif self._response_mode == "json_mode":
            body["response_format"] = {"type": "json_object"}
        elif self._response_mode == "raw":
            # No response_format, extract JSON from text
            pass
        else:
            raise RecognitionProviderError(
                f"Invalid response_mode: {self._response_mode}. "
                "Must be one of: json_schema, json_mode, raw"
            )

        return body

    def _extract_response(self, payload: dict[str, Any]) -> RecognitionResponse:
        """Extract RecognitionResponse from OpenAI API response."""
        try:
            choice = payload["choices"][0]
            message = choice["message"]
        except (KeyError, IndexError, TypeError) as exc:
            raise RecognitionProviderError(f"Malformed OpenAI response: {exc}") from exc

        # Try to get content from various locations
        content = None

        # Check for parsed content (json_schema mode)
        if isinstance(message.get("parsed"), dict):
            content = json.dumps(message["parsed"])
        # Check for content string (json_mode or raw)
        elif isinstance(message.get("content"), str):
            content = message["content"]
        # Check for content array (newer API versions)
        elif isinstance(message.get("content"), list):
            text_parts = []
            for item in message["content"]:
                if isinstance(item, dict) and item.get("type") in {
                    "text",
                    "output_text",
                }:
                    text_value = item.get("text")
                    if isinstance(text_value, str):
                        text_parts.append(text_value)
            if text_parts:
                content = "".join(text_parts)

        if content is None:
            raise RecognitionProviderError(
                f"Recognition response did not contain valid content: {message}"
            )

        # Parse based on mode
        if self._response_mode in {"json_schema", "json_mode"}:
            return parse_recognition_response(content)
        else:  # raw mode
            json_str = extract_json_from_text(content)
            return parse_recognition_response(json_str)
