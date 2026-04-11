from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status

from app.logging_config import get_logger
from app.models.recognition import RecognitionResponse, RecognitionUploadMetadata
from app.services.artifact_store import get_artifact_store
from app.services.llm.pricing import estimate_cost
from app.services.recognizer import (
    RecognitionConfigurationError,
    RecognitionProviderError,
    _encode_crop_image,
    get_recognition_service,
)

logger = get_logger(__name__)

router = APIRouter()


@router.post("/recognitions", response_model=RecognitionResponse)
def create_recognition(
    image: UploadFile = File(...),
    prompt_version: str = Form(default="card-recognition.md"),
) -> RecognitionResponse:
    if not image.content_type or not image.content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Uploaded file must be an image.",
        )

    image_bytes = image.file.read()

    metadata = RecognitionUploadMetadata(
        filename=image.filename or "upload",
        content_type=image.content_type or "application/octet-stream",
        prompt_version=prompt_version,
    )
    try:
        response, enriched_metadata, detection_result, validation_result, usage = (
            get_recognition_service().recognize(
                image_bytes=image_bytes,
                metadata=metadata,
            )
        )
    except RecognitionConfigurationError as exc:
        logger.error(
            "Recognition configuration error: filename=%s content_type=%s error=%s",
            metadata.filename,
            metadata.content_type,
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from exc
    except RecognitionProviderError as exc:
        logger.error(
            "Recognition provider error: filename=%s content_type=%s error=%s",
            metadata.filename,
            metadata.content_type,
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc

    cost = estimate_cost(usage, enriched_metadata.model) if usage is not None else None
    get_artifact_store().save_recognition(
        image_bytes=image_bytes,
        metadata=enriched_metadata,
        response=response,
        detection_result=detection_result,
        validation_result=validation_result,
        usage=usage,
        estimated_cost_usd=cost,
    )
    return response


@router.post("/recognitions/batch", response_model=RecognitionResponse)
def create_recognition_batch(
    images: list[UploadFile] = File(...),
    prompt_version: str = Form(default="card-recognition.md"),
) -> RecognitionResponse:
    """Recognize cards from multiple pre-cropped images (client-side crops).

    Each image is a first-pass crop of a single card. All recognized cards are
    merged into a single RecognitionResponse. If no images are provided, returns
    an empty result.
    """
    if not images:
        return RecognitionResponse(cards=[])

    for img in images:
        if not img.content_type or not img.content_type.startswith("image/"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"All uploaded files must be images. Got: {img.content_type!r}",
            )

    service = get_recognition_service()
    artifact_store = get_artifact_store()

    from app.models.recognition import RecognizedCard

    all_cards: list[RecognizedCard] = []

    for i, img in enumerate(images):
        image_bytes = img.file.read()
        metadata = RecognitionUploadMetadata(
            filename=img.filename or f"crop-{i}.jpg",
            content_type=img.content_type or "application/octet-stream",
            prompt_version=prompt_version,
        )
        try:
            response, enriched_metadata, detection_result, validation_result, usage = (
                service.recognize(
                    image_bytes=image_bytes,
                    metadata=metadata,
                    skip_detection=True,
                )
            )
        except RecognitionConfigurationError as exc:
            logger.error(
                "Batch recognition configuration error: filename=%s content_type=%s error=%s",
                metadata.filename,
                metadata.content_type,
                exc,
            )
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=str(exc),
            ) from exc
        except RecognitionProviderError as exc:
            logger.error(
                "Batch recognition provider error: filename=%s content_type=%s error=%s",
                metadata.filename,
                metadata.content_type,
                exc,
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=str(exc),
            ) from exc

        cost = estimate_cost(usage, enriched_metadata.model) if usage is not None else None
        artifact_store.save_recognition(
            image_bytes=image_bytes,
            metadata=enriched_metadata,
            response=response,
            detection_result=detection_result,
            validation_result=validation_result,
            usage=usage,
            estimated_cost_usd=cost,
        )
        encoded_crop = _encode_crop_image(image_bytes)
        for card in response.cards:
            all_cards.append(card.model_copy(update={"crop_image_data": encoded_crop}))

    return RecognitionResponse(cards=all_cards)
