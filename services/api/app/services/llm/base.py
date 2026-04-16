"""Base LLM Provider interface and shared utilities."""

import base64
import json
import logging
import re
from typing import Any, Protocol

from app.models.recognition import RecognitionResponse, RecognitionResult, TokenUsage
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
    ) -> RecognitionResult: ...


def extract_openai_usage(payload: dict[str, Any]) -> TokenUsage | None:
    """Extract token usage from an OpenAI-compatible API response."""
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        return None
    return TokenUsage(
        input_tokens=usage.get("prompt_tokens", 0),
        output_tokens=usage.get("completion_tokens", 0),
        total_tokens=usage.get("total_tokens", 0),
    )


def extract_anthropic_usage(payload: dict[str, Any]) -> TokenUsage | None:
    """Extract token usage from an Anthropic API response."""
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        return None
    input_t = usage.get("input_tokens", 0)
    output_t = usage.get("output_tokens", 0)
    return TokenUsage(
        input_tokens=input_t,
        output_tokens=output_t,
        total_tokens=input_t + output_t,
    )


def encode_image_to_data_url(image_bytes: bytes, content_type: str) -> str:
    """Encode image bytes to base64 data URL."""
    encoded = base64.b64encode(image_bytes).decode("ascii")
    return f"data:{content_type};base64,{encoded}"


CORNER_CROP_PRESENT_TEXT = (
    "Close-up of the bottom-left corner of the same card. "
    "Look carefully at the left side of the info strip: "
    "is there a small white icon to the LEFT of the collector number? "
    "Use this to determine list_reprint."
)

CORNER_CROP_ABSENT_TEXT = (
    "No close-up image is provided. Make the List/Mystery Booster "
    "determination from the full card image alone. If the planeswalker "
    "icon is not clearly visible at that resolution, set list_reprint "
    'to "possible" rather than guessing.'
)


def maybe_corner_crop(image_bytes: bytes, enabled: bool) -> bytes | None:
    """Return corner crop bytes when enabled and crop succeeds, else None."""
    if not enabled:
        return None
    corner = crop_bottom_left_corner(image_bytes)
    return corner or None


def crop_bottom_left_corner(image_bytes: bytes) -> bytes:
    """Crop the bottom-left corner of a card image (List symbol area).

    Returns a JPEG crop of the bottom-left 50% width × 20% height of the image.
    This size is required so the model can distinguish the two stacked icons
    (List symbol on line 1, MTG hourglass on line 2) as separate elements.
    """
    try:
        import cv2
        import numpy as np

        arr = np.frombuffer(image_bytes, dtype=np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            return b""
        h, w = img.shape[:2]
        y0 = int(h * 0.80)
        x1 = int(w * 0.50)
        crop = img[y0:h, 0:x1]
        ok, buf = cv2.imencode(".jpg", crop, [cv2.IMWRITE_JPEG_QUALITY, 92])
        return buf.tobytes() if ok else b""
    except Exception:
        logger.debug("crop_bottom_left_corner failed, skipping corner crop")
        return b""


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
