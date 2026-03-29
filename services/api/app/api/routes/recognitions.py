from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status

from app.models.recognition import RecognitionResponse, RecognitionUploadMetadata
from app.services.artifact_store import get_artifact_store
from app.services.recognizer import (
    RecognitionConfigurationError,
    RecognitionProviderError,
    _encode_crop_image,
    get_recognition_service,
)

router = APIRouter()


@router.post("/recognitions", response_model=RecognitionResponse)
async def create_recognition(
    image: UploadFile = File(...),
    prompt_version: str = Form(default="card-recognition.md"),
) -> RecognitionResponse:
    if not image.content_type or not image.content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Uploaded file must be an image.",
        )

    image_bytes = await image.read()

    metadata = RecognitionUploadMetadata(
        filename=image.filename or "upload",
        content_type=image.content_type or "application/octet-stream",
        prompt_version=prompt_version,
    )
    try:
        response, enriched_metadata, detection_result, validation_result = get_recognition_service().recognize(
            image_bytes=image_bytes,
            metadata=metadata,
        )
    except RecognitionConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from exc
    except RecognitionProviderError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc

    get_artifact_store().save_recognition(
        image_bytes=image_bytes,
        metadata=enriched_metadata,
        response=response,
        detection_result=detection_result,
        validation_result=validation_result,
    )
    return response


@router.post("/recognitions/batch", response_model=RecognitionResponse)
async def create_recognition_batch(
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
        image_bytes = await img.read()
        metadata = RecognitionUploadMetadata(
            filename=img.filename or f"crop-{i}.jpg",
            content_type=img.content_type or "application/octet-stream",
            prompt_version=prompt_version,
        )
        try:
            response, enriched_metadata, detection_result, validation_result = service.recognize(
                image_bytes=image_bytes,
                metadata=metadata,
            )
        except RecognitionConfigurationError as exc:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=str(exc),
            ) from exc
        except RecognitionProviderError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=str(exc),
            ) from exc

        artifact_store.save_recognition(
            image_bytes=image_bytes,
            metadata=enriched_metadata,
            response=response,
            detection_result=detection_result,
            validation_result=validation_result,
        )
        encoded_crop = _encode_crop_image(image_bytes)
        for card in response.cards:
            all_cards.append(card.model_copy(update={"crop_image_data": encoded_crop}))

    return RecognitionResponse(cards=all_cards)
