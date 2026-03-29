from fastapi import FastAPI

from app.api.routes.cards import router as cards_router
from app.api.routes.health import router as health_router
from app.api.routes.recognitions import router as recognitions_router

app = FastAPI(title="MTG Scanner API", version="0.1.0")
app.include_router(health_router)
app.include_router(recognitions_router, prefix="/api/v1")
app.include_router(cards_router, prefix="/api/v1")
