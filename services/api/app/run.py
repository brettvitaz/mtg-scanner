import uvicorn

from app.settings import get_settings


if __name__ == "__main__":
    settings = get_settings()
    uvicorn.run(
        "app.main:app",
        app_dir="services/api",
        reload=True,
        host=settings.mtg_scanner_api_host,
        port=settings.mtg_scanner_api_port,
    )
