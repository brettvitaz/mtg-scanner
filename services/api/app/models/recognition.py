from pydantic import BaseModel, Field


class TokenUsage(BaseModel):
    """Normalized token counts from an LLM API response."""

    input_tokens: int = Field(..., ge=0)
    output_tokens: int = Field(..., ge=0)
    total_tokens: int = Field(..., ge=0)


def accumulate_usage(usages: list["TokenUsage | None"]) -> "TokenUsage | None":
    """Sum token usage across multiple LLM calls. Returns None if all inputs are None."""
    valid = [u for u in usages if u is not None]
    if not valid:
        return None
    return TokenUsage(
        input_tokens=sum(u.input_tokens for u in valid),
        output_tokens=sum(u.output_tokens for u in valid),
        total_tokens=sum(u.total_tokens for u in valid),
    )


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


class RecognitionResult(BaseModel):
    """Internal result pairing a recognition response with LLM usage metadata."""

    response: RecognitionResponse
    usage: TokenUsage | None = None
