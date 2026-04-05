import json
import logging
import re
from typing import Any

from app.models.recognition import RecognitionResponse
from app.services.errors import RecognitionProviderError

logger = logging.getLogger(__name__)


def build_openai_request_body(
    *,
    model_name: str,
    prompt_text: str,
    data_url: str,
    schema: dict,
    response_mode: str,
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "model": model_name,
        "messages": [
            {
                "role": "system",
                "content": prompt_text,
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": _user_instruction(response_mode),
                    },
                    {
                        "type": "image_url",
                        "image_url": {"url": data_url},
                    },
                ],
            },
        ],
    }

    if response_mode == "json_schema":
        body["response_format"] = {
            "type": "json_schema",
            "json_schema": {
                "name": "recognition_response",
                "schema": schema,
            },
        }
    elif response_mode == "json_mode":
        body["response_format"] = {"type": "json_object"}
    elif response_mode == "raw":
        pass
    else:
        raise RecognitionProviderError(
            "MTG_SCANNER_OPENAI_RESPONSE_MODE must be one of: json_schema, json_mode, raw."
        )

    return body


def extract_recognition_response(
    payload: dict, response_mode: str
) -> RecognitionResponse:
    content = _extract_openai_content(payload)

    if response_mode in {"json_schema", "json_mode"}:
        return _parse_recognition_json(content)
    if response_mode == "raw":
        return _parse_recognition_json(_extract_json_object(content))

    raise RecognitionProviderError(
        "MTG_SCANNER_OPENAI_RESPONSE_MODE must be one of: json_schema, json_mode, raw."
    )


def _user_instruction(response_mode: str) -> str:
    if response_mode == "raw":
        return (
            "Analyze this Magic: The Gathering card image and respond with JSON only. "
            "Do not include markdown fences or explanation text."
        )
    return "Analyze this Magic: The Gathering card image and return JSON only."


def _parse_recognition_json(content: str) -> RecognitionResponse:
    try:
        return RecognitionResponse.model_validate_json(content)
    except Exception as exc:
        logger.error(
            "Failed to parse recognition JSON: content_snippet=%s",
            content[:500],
        )
        raise RecognitionProviderError(
            "Recognition response did not match RecognitionResponse."
        ) from exc


def _extract_json_object(content: str) -> str:
    text = content.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)

    decoder = json.JSONDecoder()
    for idx, char in enumerate(text):
        if char != "{":
            continue
        try:
            _, end = decoder.raw_decode(text[idx:])
            return text[idx : idx + end]
        except json.JSONDecodeError:
            continue

    raise RecognitionProviderError(
        "Recognition response did not contain a JSON object."
    )


def _extract_openai_content(payload: dict) -> str:
    try:
        choice = payload["choices"][0]
        message = choice["message"]
    except (KeyError, IndexError, TypeError) as exc:
        available_keys = (
            list(payload.keys()) if isinstance(payload, dict) else str(type(payload))
        )
        logger.error(
            "Malformed OpenAI response: missing choices[0].message, keys=%s",
            available_keys,
        )
        raise RecognitionProviderError(
            "Recognition response was missing choices[0].message."
        ) from exc

    if isinstance(message.get("content"), str):
        return message["content"]

    parsed = message.get("parsed")
    if isinstance(parsed, dict):
        return json.dumps(parsed)

    content = message.get("content")
    if isinstance(content, list):
        text_parts: list[str] = []
        for item in content:
            if isinstance(item, dict) and item.get("type") in {"text", "output_text"}:
                text_value = item.get("text")
                if isinstance(text_value, str):
                    text_parts.append(text_value)
        if text_parts:
            return "".join(text_parts)

    logger.error(
        "Recognition response did not contain JSON content: content_type=%s content_preview=%s",
        type(content).__name__,
        str(content)[:200] if content else "<empty>",
    )
    raise RecognitionProviderError("Recognition response did not contain JSON content.")
