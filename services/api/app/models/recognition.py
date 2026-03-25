from pydantic import BaseModel, Field


class RecognitionUploadMetadata(BaseModel):
    filename: str = Field(..., description="Uploaded image filename")
    content_type: str = Field(..., description="Uploaded image MIME type")
    prompt_version: str = Field(default="card-recognition.md")
    provider: str | None = Field(default=None, description="Recognizer provider used")
    model: str | None = Field(default=None, description="Recognizer model used")


class RecognizedCard(BaseModel):
    title: str | None = None
    edition: str | None = None
    collector_number: str | None = None
    foil: bool | None = None
    confidence: float = Field(..., ge=0.0, le=1.0)
    notes: str | None = None


class RecognitionResponse(BaseModel):
    cards: list[RecognizedCard]
