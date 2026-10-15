from fastapi import APIRouter, HTTPException

from app.logging_config import get_logger
from app.models.recognition_feedback import RecognitionFeedbackRequest, RecognitionFeedbackResponse
from app.services.artifact_store import get_artifacts_base_dir
from app.services.recognition_feedback import save_feedback

router = APIRouter()
logger = get_logger(__name__)


@router.post("/recognition-feedback", response_model=RecognitionFeedbackResponse)
def recognition_feedback(event: RecognitionFeedbackRequest) -> RecognitionFeedbackResponse:
    try:
        duplicate = save_feedback(event, get_artifacts_base_dir())
    except OSError as error:
        logger.exception("Could not persist recognition feedback %s", event.event_id)
        raise HTTPException(status_code=500, detail="Could not save recognition feedback") from error
    logger.info("Recognition feedback %s acknowledged (duplicate=%s)", event.event_id, duplicate)
    return RecognitionFeedbackResponse(event_id=event.event_id, duplicate=duplicate)
