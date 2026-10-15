import base64
import binascii
from typing import Literal
from uuid import UUID

import cv2
import numpy as np
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, JsonValue, field_validator


class FeedbackIdentification(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str
    edition: str
    foil: bool
    set_code: str | None = None
    collector_number: str | None = None
    scryfall_id: str | None = None


class RecognitionFeedbackRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    event_id: UUID
    created_at: AwareDatetime
    original_recognition: dict[str, JsonValue]
    previous_identification: FeedbackIdentification
    corrected_identification: FeedbackIdentification
    scan_jpeg: str = Field(max_length=4_000_000)

    @field_validator("scan_jpeg")
    @classmethod
    def validate_jpeg(cls, value: str) -> str:
        try:
            data = base64.b64decode(value, validate=True)
        except (ValueError, binascii.Error) as error:
            raise ValueError("scan_jpeg must be base64 JPEG data") from error
        if not data.startswith(b"\xff\xd8"):
            raise ValueError("scan_jpeg must be a JPEG")
        try:
            image = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)
        except cv2.error as error:
            raise ValueError("scan_jpeg could not be decoded") from error
        if image is None or max(image.shape[:2]) > 1000:
            raise ValueError("scan_jpeg must be a usable JPEG with a maximum edge of 1000 pixels")
        return value


class RecognitionFeedbackResponse(BaseModel):
    event_id: UUID
    accepted: Literal[True] = True
    duplicate: bool
