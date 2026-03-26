import base64
import json
from pathlib import Path
from typing import Protocol

import httpx

from app.models.recognition import (
    RecognizedCard,
    RecognitionResponse,
    RecognitionUploadMetadata,
)
from app.services.card_detector import CardDetector, DetectionResult
from app.services.errors import RecognitionConfigurationError, RecognitionProviderError
from app.services.openai_compat import (
    build_openai_request_body,
    extract_recognition_response,
)
from app.settings import get_settings


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
        response_mode: str = "json_schema",
    ) -> None:
        self.model_name = model_name
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._timeout_seconds = timeout_seconds
        self._response_mode = response_mode
        self._response_schema = _load_response_schema()

    def recognize(
        self,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
        prompt_text: str,
    ) -> RecognitionResponse:
        request_body = build_openai_request_body(
            model_name=self.model_name,
            prompt_text=prompt_text,
            data_url=_make_data_url(
                content_type=metadata.content_type,
                image_bytes=image_bytes,
            ),
            schema=self._response_schema,
            response_mode=self._response_mode,
        )

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
        return extract_recognition_response(payload, self._response_mode)


class RecognitionService:
    def __init__(
        self,
        provider: RecognitionProvider,
        card_detector: CardDetector | None = None,
    ) -> None:
        self._provider = provider
        self._card_detector = card_detector

    def recognize(
        self,
        *,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
    ) -> tuple[RecognitionResponse, RecognitionUploadMetadata, DetectionResult | None]:
        """Recognize cards in an image.

        If a card detector is configured and multiple cards are detected,
        each card is cropped and recognized individually.

        Returns:
            Tuple of (RecognitionResponse, enriched metadata, detection result)
        """
        prompt_text = _load_prompt(metadata.prompt_version)
        enriched_metadata = metadata.model_copy(
            update={
                "provider": self._provider.provider_name,
                "model": self._provider.model_name,
            }
        )

        # Try multi-card detection if detector is available
        detection_result: DetectionResult | None = None
        if self._card_detector is not None:
            detection_result = self._card_detector.detect(image_bytes)

            if detection_result.count > 1:
                # Multiple cards detected - recognize each individually
                all_cards: list[RecognizedCard] = []
                for i, region in enumerate(detection_result.regions):
                    crop_bytes, crop_content_type = self._card_detector.crop_region(
                        image_bytes, region
                    )
                    crop_metadata = enriched_metadata.model_copy(
                        update={
                            "filename": f"{metadata.filename}-crop-{i}.jpg",
                            "content_type": crop_content_type,
                        }
                    )
                    response = self._provider.recognize(
                        image_bytes=crop_bytes,
                        metadata=crop_metadata,
                        prompt_text=prompt_text,
                    )
                    all_cards.extend(response.cards)

                return RecognitionResponse(cards=all_cards), enriched_metadata, detection_result

        # Single card or no detection - use original behavior
        response = self._provider.recognize(
            image_bytes=image_bytes,
            metadata=enriched_metadata,
            prompt_text=prompt_text,
        )
        return response, enriched_metadata, detection_result


def get_recognition_service() -> RecognitionService:
    settings = get_settings()
    provider_name = settings.mtg_scanner_recognizer_provider.strip().lower()

    detector: CardDetector | None = None
    if settings.mtg_scanner_enable_multi_card:
        from app.services.card_detector import get_card_detector
        detector = get_card_detector()

    if provider_name == "mock":
        return RecognitionService(MockRecognitionProvider(), detector)

    if provider_name == "openai":
        api_key = settings.openai_api_key
        if not api_key:
            raise RecognitionConfigurationError(
                "OPENAI_API_KEY must be set when MTG_SCANNER_RECOGNIZER_PROVIDER=openai."
            )

        model_name = settings.mtg_scanner_openai_model
        if not model_name:
            raise RecognitionConfigurationError(
                "MTG_SCANNER_OPENAI_MODEL must be set when MTG_SCANNER_RECOGNIZER_PROVIDER=openai."
            )

        return RecognitionService(
            OpenAIRecognitionProvider(
                api_key=api_key,
                model_name=model_name,
                base_url=settings.openai_base_url,
                timeout_seconds=settings.mtg_scanner_openai_timeout_seconds,
                response_mode=settings.mtg_scanner_openai_response_mode.strip().lower(),
            ),
            detector,
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

