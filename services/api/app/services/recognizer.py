import base64
import concurrent.futures
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
from app.services.card_validation import CardValidationService, ValidationBatchResult
from app.services.errors import RecognitionConfigurationError, RecognitionProviderError
from app.services.mtgjson_index import CardRecord, MTGJSONIndex
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
    provider_name: str = "mock"
    model_name: str | None = None

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
    provider_name: str = "openai"

    def __init__(
        self,
        *,
        api_key: str,
        model_name: str,
        base_url: str,
        timeout_seconds: float = 30.0,
        response_mode: str = "json_schema",
    ) -> None:
        self.model_name: str | None = model_name
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
        assert self.model_name is not None
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
        validator: CardValidationService | None = None,
        max_concurrent_recognitions: int = 4,
        enable_llm_correction: bool = True,
        correction_prompt_version: str = "card-correction.md",
    ) -> None:
        self._provider = provider
        self._card_detector = card_detector
        self._validator = validator
        self._max_concurrent_recognitions = max(1, max_concurrent_recognitions)
        self._enable_llm_correction = enable_llm_correction
        self._correction_prompt_version = correction_prompt_version

    def _validate_response(
        self,
        response: RecognitionResponse,
    ) -> ValidationBatchResult | None:
        if self._validator is None:
            return None
        return self._validator.validate_response(response)

    def _apply_llm_correction(
        self,
        validation_result: ValidationBatchResult,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
    ) -> ValidationBatchResult:
        """Re-query the LLM for any cards with needs_correction status.

        Builds a constrained correction prompt with valid candidate printings and
        calls the provider again. Falls back to the original result if correction fails.
        """
        if not self._enable_llm_correction or self._validator is None:
            return validation_result

        needs_correction_indices = [
            i for i, trace in enumerate(validation_result.traces)
            if trace.status == "needs_correction"
        ]
        if not needs_correction_indices:
            return validation_result

        correction_prompt_text = _load_prompt(self._correction_prompt_version)
        updated_cards = list(validation_result.response.cards)
        updated_traces = list(validation_result.traces)
        updated_candidates = list(validation_result.correction_candidates)

        for idx in needs_correction_indices:
            card = validation_result.response.cards[idx]
            candidates = validation_result.correction_candidates[idx]
            reason = validation_result.traces[idx].reason

            filled_prompt = _build_correction_prompt(
                correction_prompt_text, card, candidates, reason
            )
            try:
                corrected_response = self._provider.recognize(
                    image_bytes=image_bytes,
                    metadata=metadata,
                    prompt_text=filled_prompt,
                )
            except RecognitionProviderError:
                continue

            if not corrected_response.cards:
                continue

            corrected_card = corrected_response.cards[0]
            re_validated = self._validator.validate_card(corrected_card)

            if re_validated.trace.status not in {"no_match", "needs_correction"}:
                updated_cards[idx] = re_validated.card
                updated_traces[idx] = re_validated.trace
                updated_candidates[idx] = re_validated.correction_candidates

        return ValidationBatchResult(
            response=RecognitionResponse(cards=updated_cards),
            traces=updated_traces,
            enabled=validation_result.enabled,
            available=validation_result.available,
            correction_candidates=updated_candidates,
        )

    def _recognize_multiple_crops(
        self,
        *,
        crops: list[tuple[bytes, RecognitionUploadMetadata]],
        prompt_text: str,
    ) -> list[RecognitionResponse]:
        executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=self._max_concurrent_recognitions
        )
        shutdown_nowait = False
        try:
            responses: list[RecognitionResponse | None] = [None] * len(crops)
            indexed_crops = iter(enumerate(crops))
            futures: dict[concurrent.futures.Future[RecognitionResponse], int] = {}

            def submit_next_crop() -> bool:
                try:
                    index, (crop_bytes, crop_metadata) = next(indexed_crops)
                except StopIteration:
                    return False
                futures[
                    executor.submit(
                        self._provider.recognize,
                        crop_bytes,
                        crop_metadata,
                        prompt_text,
                    )
                ] = index
                return True

            for _ in range(min(self._max_concurrent_recognitions, len(crops))):
                submit_next_crop()

            while futures:
                done, _ = concurrent.futures.wait(
                    futures,
                    return_when=concurrent.futures.FIRST_COMPLETED,
                )
                for future in done:
                    index = futures.pop(future)
                    try:
                        responses[index] = future.result()
                    except Exception:
                        for pending_future in futures:
                            pending_future.cancel()
                        executor.shutdown(wait=False, cancel_futures=True)
                        shutdown_nowait = True
                        raise
                    submit_next_crop()

            return [response for response in responses if response is not None]
        finally:
            if not shutdown_nowait:
                executor.shutdown(wait=True)

    def recognize(
        self,
        *,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
    ) -> tuple[
        RecognitionResponse,
        RecognitionUploadMetadata,
        DetectionResult | None,
        ValidationBatchResult | None,
    ]:
        """Recognize cards in an image.

        If a card detector is configured and multiple cards are detected,
        each card is cropped and recognized individually.

        Returns:
            Tuple of (RecognitionResponse, enriched metadata, detection result, validation result)
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
                crops: list[tuple[bytes, RecognitionUploadMetadata]] = []
                crop_bytes_list: list[bytes] = []
                for i, region in enumerate(detection_result.regions):
                    crop_bytes, crop_content_type = self._card_detector.crop_region(
                        image_bytes, region
                    )
                    crop_bytes_list.append(crop_bytes)
                    crop_metadata = enriched_metadata.model_copy(
                        update={
                            "filename": f"{metadata.filename}-crop-{i}.jpg",
                            "content_type": crop_content_type,
                        }
                    )
                    crops.append((crop_bytes, crop_metadata))

                crop_responses = self._recognize_multiple_crops(
                    crops=crops,
                    prompt_text=prompt_text,
                )

                all_cards: list[RecognizedCard] = []
                for response in crop_responses:
                    all_cards.extend(response.cards)

                combined_response = RecognitionResponse(cards=all_cards)
                validation_result = self._validate_response(combined_response)
                if validation_result:
                    validation_result = self._apply_llm_correction(
                        validation_result, image_bytes, enriched_metadata
                    )
                final_response = validation_result.response if validation_result else combined_response
                final_response = _attach_crop_images(final_response, crop_bytes_list)
                return (
                    final_response,
                    enriched_metadata,
                    detection_result,
                    validation_result,
                )

        # Single card or no detection - use original behavior
        response = self._provider.recognize(
            image_bytes=image_bytes,
            metadata=enriched_metadata,
            prompt_text=prompt_text,
        )
        validation_result = self._validate_response(response)
        if validation_result:
            validation_result = self._apply_llm_correction(
                validation_result, image_bytes, enriched_metadata
            )
        return (
            validation_result.response if validation_result else response,
            enriched_metadata,
            detection_result,
            validation_result,
        )


def get_recognition_service() -> RecognitionService:
    settings = get_settings()
    provider_name = settings.mtg_scanner_recognizer_provider.strip().lower()

    detector: CardDetector | None = None
    if settings.mtg_scanner_enable_multi_card:
        from app.services.card_detector import get_card_detector
        detector = get_card_detector()

    validator: CardValidationService | None = None
    if settings.mtg_scanner_enable_mtg_validation:
        validator = CardValidationService(
            index=MTGJSONIndex(Path(settings.mtg_scanner_mtgjson_db_path).expanduser()),
            max_fuzzy_candidates=settings.mtg_scanner_mtgjson_max_fuzzy_candidates,
        )

    if provider_name == "mock":
        return RecognitionService(
            MockRecognitionProvider(),
            detector,
            validator,
            max_concurrent_recognitions=settings.mtg_scanner_max_concurrent_recognitions,
            enable_llm_correction=settings.mtg_scanner_enable_llm_correction,
            correction_prompt_version=settings.mtg_scanner_correction_prompt_version,
        )

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
            validator,
            max_concurrent_recognitions=settings.mtg_scanner_max_concurrent_recognitions,
            enable_llm_correction=settings.mtg_scanner_enable_llm_correction,
            correction_prompt_version=settings.mtg_scanner_correction_prompt_version,
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


def _encode_crop_image(image_bytes: bytes, quality: int = 60) -> str:
    """Compress a crop image to JPEG and encode as base64."""
    import cv2
    import numpy as np

    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        return base64.b64encode(image_bytes).decode("ascii")
    _, jpeg_bytes = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])
    return base64.b64encode(jpeg_bytes.tobytes()).decode("ascii")


def _attach_crop_images(
    response: RecognitionResponse,
    crop_bytes_list: list[bytes],
) -> RecognitionResponse:
    """Attach base64-encoded crop images to recognized cards by index."""
    updated_cards: list[RecognizedCard] = []
    for i, card in enumerate(response.cards):
        if i < len(crop_bytes_list):
            encoded = _encode_crop_image(crop_bytes_list[i])
            updated_cards.append(card.model_copy(update={"crop_image_data": encoded}))
        else:
            updated_cards.append(card)
    return RecognitionResponse(cards=updated_cards)


def _build_correction_prompt(
    template: str,
    card: RecognizedCard,
    candidates: list[CardRecord],
    reason: str,
) -> str:
    """Fill the correction prompt template with card data and candidate table."""
    rows = ["| Set Name | Set Code | Collector # | Rarity | Finishes |", "| --- | --- | --- | --- | --- |"]
    for c in candidates:
        finishes_display = c.finishes or "unknown"
        rows.append(
            f"| {c.set_name or ''} | {c.set_code} | {c.collector_number or ''} | {c.rarity or ''} | {finishes_display} |"
        )
    candidates_table = "\n".join(rows)

    filled = template
    filled = filled.replace("{{title}}", card.title or "")
    filled = filled.replace("{{edition}}", card.edition or "")
    filled = filled.replace("{{collector_number}}", card.collector_number or "")
    filled = filled.replace("{{foil}}", str(card.foil) if card.foil is not None else "unknown")
    filled = filled.replace("{{reason}}", reason)
    filled = filled.replace("{{candidates_table}}", candidates_table)
    return filled
