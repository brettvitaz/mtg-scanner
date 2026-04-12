from pathlib import Path

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel

from app.services.ck_prices import CKPriceIndex
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
    color_identity: str | None = None
    finishes: str | None = None


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
            color_identity=r.color_identity,
            finishes=r.finishes,
        )
        for r in records
    ]

    return CardPrintingsResponse(printings=printings)


class CardSearchResponse(BaseModel):
    names: list[str]


@router.get("/cards/search", response_model=CardSearchResponse)
async def search_card_names(
    q: str = Query(..., min_length=2, description="Card name search query (prefix match for single term, substring match for multiple terms)"),
    limit: int = Query(default=20, ge=1, le=50, description="Maximum results"),
) -> CardSearchResponse:
    settings = get_settings()
    index = MTGJSONIndex(Path(settings.mtg_scanner_mtgjson_db_path))

    if not index.is_available():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="MTGJSON database is not available.",
        )

    names = index.search_names_by_prefix(query=q, limit=limit)
    return CardSearchResponse(names=names)


class CardPriceResponse(BaseModel):
    price_retail: str | None = None
    qty_retail: int | None = None
    price_buy: str | None = None
    qty_buying: int | None = None
    url: str | None = None


@router.get("/cards/price", response_model=CardPriceResponse)
async def get_card_price(
    name: str = Query(..., description="Card name"),
    scryfall_id: str | None = Query(default=None, description="Scryfall UUID"),
    is_foil: bool = Query(default=False, description="Whether the card is foil"),
) -> CardPriceResponse:
    settings = get_settings()
    if not settings.mtg_scanner_enable_ck_prices:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Card Kingdom pricing is not enabled.",
        )

    index = CKPriceIndex(Path(settings.mtg_scanner_ck_prices_db_path))
    if not index.is_available():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Card Kingdom price database is not available.",
        )

    result = index.lookup_price(scryfall_id=scryfall_id, name=name, is_foil=is_foil)
    if result is None:
        return CardPriceResponse()

    return CardPriceResponse(
        price_retail=result.price_retail,
        qty_retail=result.qty_retail,
        price_buy=result.price_buy,
        qty_buying=result.qty_buying,
        url=result.url,
    )
