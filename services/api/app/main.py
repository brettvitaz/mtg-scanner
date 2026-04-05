import time
import uuid

from fastapi import FastAPI, Request
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import Response

from app.api.routes.cards import router as cards_router
from app.api.routes.health import router as health_router
from app.api.routes.recognitions import router as recognitions_router
from app.logging_config import get_logger, set_request_id, setup_logging

setup_logging()

logger = get_logger(__name__)


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        request_id = request.headers.get("X-Request-Id") or str(uuid.uuid4())
        set_request_id(request_id)
        start = time.monotonic()

        response = await call_next(request)

        duration_ms = (time.monotonic() - start) * 1000
        logger.info(
            "%s %s %d %.0fms",
            request.method,
            request.url.path,
            response.status_code,
            duration_ms,
        )
        response.headers["X-Request-Id"] = request_id
        return response


app = FastAPI(title="MTG Scanner API", version="0.1.0")
app.add_middleware(RequestIdMiddleware)
app.include_router(health_router)
app.include_router(recognitions_router, prefix="/api/v1")
app.include_router(cards_router, prefix="/api/v1")


@app.on_event("startup")
async def on_startup() -> None:
    logger.info("MTG Scanner API starting")


@app.on_event("shutdown")
async def on_shutdown() -> None:
    logger.info("MTG Scanner API shutting down")
