"""Base LLM Provider interface and shared utilities."""

import base64
import json
import logging
import re
from typing import Any, Protocol

from app.models.recognition import RecognitionResponse
from app.services.errors import RecognitionProviderError

logger = logging.getLogger(__name__)


class LLMProvider(Protocol):
    """Protocol for LLM providers."""

    provider_name: str
    model_name: str | None

    def recognize(
        self,
        image_bytes: bytes,
        metadata: Any,
        prompt_text: str,
    ) -> RecognitionResponse: ...


def encode_image_to_data_url(image_bytes: bytes, content_type: str) -> str:
    """Encode image bytes to base64 data URL."""
    encoded = base64.b64encode(image_bytes).decode("ascii")
    return f"data:{content_type};base64,{encoded}"


def extract_json_from_text(text: str) -> str:
    """Extract JSON object from text, handling markdown fences and partial content.

    Args:
        text: Text that may contain a JSON object

    Returns:
        Extracted JSON string

    Raises:
        RecognitionProviderError: If no valid JSON object found
    """
    # Strip markdown code fences
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```$", "", cleaned)

    # Find first valid JSON object
    decoder = json.JSONDecoder()
    for idx, char in enumerate(cleaned):
        if char != "{":
            continue
        try:
            _, end = decoder.raw_decode(cleaned[idx:])
            return cleaned[idx : idx + end]
        except json.JSONDecodeError:
            continue

    raise RecognitionProviderError(
        f"Recognition response did not contain a JSON object. Content preview: {text[:200]}"
    )


def parse_recognition_response(content: str) -> RecognitionResponse:
    """Parse JSON content into RecognitionResponse model.

    Args:
        content: JSON string to parse

    Returns:
        Validated RecognitionResponse

    Raises:
        RecognitionProviderError: If parsing or validation fails
    """
    try:
        return RecognitionResponse.model_validate_json(content)
    except Exception as exc:
        logger.error(
            "Failed to parse recognition JSON: content_snippet=%s",
            content[:500],
        )
        raise RecognitionProviderError(
            "Recognition response did not match RecognitionResponse schema."
        ) from exc
