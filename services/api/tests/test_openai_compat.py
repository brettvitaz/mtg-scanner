import json

import pytest

from app.services.openai_compat import (
    build_openai_request_body,
    extract_recognition_response,
)
from app.services.recognizer import RecognitionProviderError


SCHEMA = {"type": "object"}
DATA_URL = "data:image/jpeg;base64,Zm9v"
PROMPT = "Return recognition JSON"


def _payload_with_content(content):
    return {"choices": [{"message": {"content": content}}]}


def test_build_openai_request_body_json_schema():
    body = build_openai_request_body(
        model_name="gpt-4.1-mini",
        prompt_text=PROMPT,
        data_url=DATA_URL,
        schema=SCHEMA,
        response_mode="json_schema",
    )
    assert body["response_format"]["type"] == "json_schema"


def test_build_openai_request_body_json_mode():
    body = build_openai_request_body(
        model_name="llama3.2-vision",
        prompt_text=PROMPT,
        data_url=DATA_URL,
        schema=SCHEMA,
        response_mode="json_mode",
    )
    assert body["response_format"]["type"] == "json_object"


def test_build_openai_request_body_raw_mode():
    body = build_openai_request_body(
        model_name="local-model",
        prompt_text=PROMPT,
        data_url=DATA_URL,
        schema=SCHEMA,
        response_mode="raw",
    )
    assert "response_format" not in body


def test_extract_recognition_response_raw_markdown_wrapped_json():
    payload = _payload_with_content(
        "```json\n{\"cards\":[{\"title\":\"Lightning Bolt\",\"edition\":\"M11\",\"collector_number\":\"146\",\"foil\":false,\"confidence\":0.95}]}\n```"
    )
    result = extract_recognition_response(payload, "raw")
    assert result.cards[0].title == "Lightning Bolt"


def test_extract_recognition_response_invalid_mode():
    with pytest.raises(RecognitionProviderError):
        build_openai_request_body(
            model_name="bad",
            prompt_text=PROMPT,
            data_url=DATA_URL,
            schema=SCHEMA,
            response_mode="bogus",
        )


def test_extract_recognition_response_raw_rejects_non_json():
    payload = _payload_with_content("not json at all")
    with pytest.raises(RecognitionProviderError):
        extract_recognition_response(payload, "raw")
