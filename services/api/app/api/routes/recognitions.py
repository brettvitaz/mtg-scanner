from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status

from app.models.recognition import RecognitionResponse, RecognitionUploadMetadata
from app.services.artifact_store import get_artifact_store
from app.services.recognizer import (
    RecognitionConfigurationError,
    RecognitionProviderError,
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
        content_type=image.content_type,
        prompt_version=prompt_version,
    )
    try:
        response, enriched_metadata = get_recognition_service().recognize(
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
    )
    return response
