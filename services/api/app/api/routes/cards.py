from pathlib import Path

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel

from app.services.mtgjson_index import MTGJSONIndex
from app.settings import get_settings

router = APIRouter()


class CardPrinting(BaseModel):
    name: str
    set_code: str
    set_name: str | None = None
    collector_number: str | None = None
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


class CardPrintingsResponse(BaseModel):
    printings: list[CardPrinting]


def _build_image_url(scryfall_id: str | None) -> str | None:
    if not scryfall_id:
        return None
    return f"https://api.scryfall.com/cards/{scryfall_id}?format=image&version=normal"


def _build_set_symbol_url(set_code: str | None) -> str | None:
    if not set_code:
        return None
    return f"https://svgs.scryfall.io/sets/{set_code.lower()}.svg"


@router.get("/cards/printings", response_model=CardPrintingsResponse)
async def get_card_printings(
    name: str = Query(..., description="Card name to look up printings for"),
) -> CardPrintingsResponse:
    settings = get_settings()
    index = MTGJSONIndex(Path(settings.mtg_scanner_mtgjson_db_path))

    if not index.is_available():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="MTGJSON database is not available.",
        )

    records = index.lookup_all_printings_by_name(title=name)

    printings = [
        CardPrinting(
            name=r.name,
            set_code=r.set_code,
            set_name=r.set_name,
            collector_number=r.collector_number,
            rarity=r.rarity,
            type_line=r.type_line,
            oracle_text=r.oracle_text,
            mana_cost=r.mana_cost,
            power=r.power,
            toughness=r.toughness,
            loyalty=r.loyalty,
            defense=r.defense,
            scryfall_id=r.scryfall_id,
            image_url=_build_image_url(r.scryfall_id),
            set_symbol_url=_build_set_symbol_url(r.set_code),
            card_kingdom_url=r.card_kingdom_url,
            card_kingdom_foil_url=r.card_kingdom_foil_url,
        )
        for r in records
    ]

    return CardPrintingsResponse(printings=printings)
