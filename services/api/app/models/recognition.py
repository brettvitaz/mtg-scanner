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
    set_code: str | None = None
    rarity: str | None = None
    type_line: str | None = None
    oracle_text: str | None = None
    mana_cost: str | None = None
    power: str | None = None
    toughness: str | None = None
    loyalty: str | None = None
    defense: str | None = None
    scryfall_id: str | None = None
    image_url: str | None = None
    set_symbol_url: str | None = None
    card_kingdom_url: str | None = None
    card_kingdom_foil_url: str | None = None
    color_identity: str | None = None
    crop_image_data: str | None = Field(default=None, description="Base64-encoded JPEG crop image")


class RecognitionResponse(BaseModel):
    cards: list[RecognizedCard]
