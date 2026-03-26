from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


_ENV_FILES = [
    Path(__file__).resolve().parents[1] / ".env",
    Path(__file__).resolve().parents[1] / ".env.local",
]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=tuple(str(path) for path in _ENV_FILES),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    mtg_scanner_api_host: str = Field(default="127.0.0.1")
    mtg_scanner_api_port: int = Field(default=8000)
    mtg_scanner_recognizer_provider: str = Field(default="mock")
    mtg_scanner_enable_multi_card: bool = Field(default=True)
    mtg_scanner_artifacts_dir: str | None = Field(default=None)

    openai_api_key: str | None = Field(default=None, alias="OPENAI_API_KEY")
    mtg_scanner_openai_model: str | None = Field(default=None)
    openai_base_url: str = Field(default="https://api.openai.com/v1", alias="OPENAI_BASE_URL")
    mtg_scanner_openai_response_mode: str = Field(default="json_schema")


def get_settings() -> Settings:
    return Settings()
