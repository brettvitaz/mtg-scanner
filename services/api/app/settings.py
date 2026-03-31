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
    mtg_scanner_max_concurrent_recognitions: int = Field(default=4)
    mtg_scanner_artifacts_dir: str | None = Field(default=None)
    mtg_scanner_enable_mtg_validation: bool = Field(default=True)
    mtg_scanner_mtgjson_db_path: str = Field(default=str(Path(__file__).resolve().parents[1] / "data" / "mtgjson" / "mtgjson.sqlite"))
    mtg_scanner_mtgjson_source_path: str = Field(default=str(Path(__file__).resolve().parents[3] / "tmp" / "AllPrintings.json"))
    mtg_scanner_mtgjson_max_fuzzy_candidates: int = Field(default=10)

    mtg_scanner_enable_ck_prices: bool = Field(default=False)
    mtg_scanner_ck_prices_db_path: str = Field(default=str(Path(__file__).resolve().parents[1] / "data" / "ck_prices" / "ck_prices.sqlite"))
    mtg_scanner_ck_prices_url: str = Field(default="https://www.cardkingdom.com/assets/json/product_catalog.json")

    openai_api_key: str | None = Field(default=None, alias="OPENAI_API_KEY")
    mtg_scanner_openai_model: str | None = Field(default=None)
    openai_base_url: str = Field(default="https://api.openai.com/v1", alias="OPENAI_BASE_URL")
    mtg_scanner_openai_timeout_seconds: float = Field(default=30.0)
    mtg_scanner_openai_response_mode: str = Field(default="json_schema")
    mtg_scanner_enable_llm_correction: bool = Field(default=True)
    mtg_scanner_correction_prompt_version: str = Field(default="card-correction.md")


def get_settings() -> Settings:
    return Settings()
