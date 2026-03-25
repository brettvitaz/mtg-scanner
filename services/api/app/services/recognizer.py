import base64
import json
import os
from pathlib import Path
from typing import Protocol

import httpx

from app.models.recognition import RecognitionResponse, RecognitionUploadMetadata


class RecognitionConfigurationError(RuntimeError):
    pass


class RecognitionProviderError(RuntimeError):
    pass


class RecognitionProvider(Protocol):
    provider_name: str
    model_name: str | None

    def recognize(
        self,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
        prompt_text: str,
    ) -> RecognitionResponse: ...


class MockRecognitionProvider:
    provider_name = "mock"
    model_name = None

    def __init__(self) -> None:
        self._example_path = (
            Path(__file__).resolve().parents[4]
            / "packages"
            / "schemas"
            / "examples"
            / "v1"
            / "recognition-response.sample.json"
        )

    def recognize(
        self,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
        prompt_text: str,
    ) -> RecognitionResponse:
        del image_bytes
        del prompt_text
        payload = json.loads(self._example_path.read_text())
        if payload.get("cards"):
            payload["cards"][0]["notes"] = (
                f"Mocked recognition result for upload '{metadata.filename}' ({metadata.content_type})."
            )
        return RecognitionResponse(**payload)


class OpenAIRecognitionProvider:
    provider_name = "openai"

    def __init__(
        self,
        *,
        api_key: str,
        model_name: str,
        base_url: str,
        timeout_seconds: float = 30.0,
    ) -> None:
        self.model_name = model_name
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._timeout_seconds = timeout_seconds
        self._response_schema = _load_response_schema()

    def recognize(
        self,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
        prompt_text: str,
    ) -> RecognitionResponse:
        request_body = {
            "model": self.model_name,
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
                            "text": "Analyze this Magic: The Gathering card image and return JSON only.",
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": _make_data_url(
                                    content_type=metadata.content_type,
                                    image_bytes=image_bytes,
                                )
                            },
                        },
                    ],
                },
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "recognition_response",
                    "schema": self._response_schema,
                },
            },
        }

        with httpx.Client(timeout=self._timeout_seconds) as client:
            try:
                http_response = client.post(
                    f"{self._base_url}/chat/completions",
                    headers={
                        "Authorization": f"Bearer {self._api_key}",
                        "Content-Type": "application/json",
                    },
                    json=request_body,
                )
                http_response.raise_for_status()
            except httpx.HTTPError as exc:
                raise RecognitionProviderError(
                    f"OpenAI recognition request failed: {exc}"
                ) from exc

        payload = http_response.json()
        content = _extract_openai_content(payload)
        try:
            return RecognitionResponse.model_validate_json(content)
        except Exception as exc:
            raise RecognitionProviderError(
                "OpenAI recognition response did not match RecognitionResponse."
            ) from exc


class RecognitionService:
    def __init__(self, provider: RecognitionProvider) -> None:
        self._provider = provider

    def recognize(
        self,
        *,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
    ) -> tuple[RecognitionResponse, RecognitionUploadMetadata]:
        prompt_text = _load_prompt(metadata.prompt_version)
        enriched_metadata = metadata.model_copy(
            update={
                "provider": self._provider.provider_name,
                "model": self._provider.model_name,
            }
        )
        response = self._provider.recognize(
            image_bytes=image_bytes,
            metadata=enriched_metadata,
            prompt_text=prompt_text,
        )
        return response, enriched_metadata


def get_recognition_service() -> RecognitionService:
    provider_name = os.environ.get("MTG_SCANNER_RECOGNIZER_PROVIDER", "mock").strip().lower()

    if provider_name == "mock":
        return RecognitionService(MockRecognitionProvider())

    if provider_name == "openai":
        api_key = os.environ.get("OPENAI_API_KEY")
        if not api_key:
            raise RecognitionConfigurationError(
                "OPENAI_API_KEY must be set when MTG_SCANNER_RECOGNIZER_PROVIDER=openai."
            )

        model_name = os.environ.get("MTG_SCANNER_OPENAI_MODEL")
        if not model_name:
            raise RecognitionConfigurationError(
                "MTG_SCANNER_OPENAI_MODEL must be set when MTG_SCANNER_RECOGNIZER_PROVIDER=openai."
            )

        base_url = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")
        return RecognitionService(
            OpenAIRecognitionProvider(
                api_key=api_key,
                model_name=model_name,
                base_url=base_url,
            )
        )

    raise RecognitionConfigurationError(
        "MTG_SCANNER_RECOGNIZER_PROVIDER must be one of: mock, openai."
    )


def _load_prompt(prompt_version: str) -> str:
    prompt_path = Path(__file__).resolve().parents[4] / "prompts" / prompt_version
    if not prompt_path.is_file():
        raise RecognitionConfigurationError(
            f"Prompt file not found for prompt_version '{prompt_version}'."
        )
    return prompt_path.read_text()


def _load_response_schema() -> dict:
    schema_path = (
        Path(__file__).resolve().parents[4]
        / "packages"
        / "schemas"
        / "v1"
        / "recognition-response.schema.json"
    )
    return json.loads(schema_path.read_text())


def _make_data_url(*, content_type: str, image_bytes: bytes) -> str:
    encoded = base64.b64encode(image_bytes).decode("ascii")
    return f"data:{content_type};base64,{encoded}"


def _extract_openai_content(payload: dict) -> str:
    try:
        choice = payload["choices"][0]
        message = choice["message"]
    except (KeyError, IndexError, TypeError) as exc:
        raise RecognitionProviderError(
            "OpenAI recognition response was missing choices[0].message."
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

    raise RecognitionProviderError(
        "OpenAI recognition response did not contain JSON content."
    )
