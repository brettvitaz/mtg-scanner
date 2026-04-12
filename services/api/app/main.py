import asyncio
import contextlib
import time
import uuid
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import Response

from app.api.routes.cards import router as cards_router
from app.api.routes.health import router as health_router
from app.api.routes.recognitions import router as recognitions_router
from app.logging_config import get_logger, set_request_id, setup_logging
from app.settings import get_settings

setup_logging()

logger = get_logger(__name__)

_pricing_task: asyncio.Task | None = None


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


settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    global _pricing_task
    logger.info("MTG Scanner API starting")
    if settings.mtg_scanner_pricing_refresh_interval_hours > 0:
        from app.services.llm.pricing_loop import pricing_refresh_loop

        _pricing_task = asyncio.create_task(
            pricing_refresh_loop(settings.mtg_scanner_pricing_refresh_interval_hours)
        )
    yield
    logger.info("MTG Scanner API shutting down")
    if _pricing_task is not None:
        _pricing_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await _pricing_task
        _pricing_task = None


app = FastAPI(title="MTG Scanner API", version="0.1.0", lifespan=lifespan)
app.add_middleware(RequestIdMiddleware)
app.include_router(health_router)
app.include_router(recognitions_router, prefix="/api/v1")
app.include_router(cards_router, prefix="/api/v1")

if settings.mtg_scanner_admin_token:
    from app.api.routes.admin import router as admin_router

    app.include_router(admin_router, prefix="/api/v1")
