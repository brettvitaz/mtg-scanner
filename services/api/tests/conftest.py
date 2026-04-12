import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

SAMPLES_DIR = Path(__file__).resolve().parents[3] / "samples" / "test"
ARTIFACTS_DIR = SAMPLES_DIR / "artifacts"

requires_sample_images = pytest.mark.skipif(
    not (SAMPLES_DIR / "IMG_1611.png").exists()
    or not (ARTIFACTS_DIR / "two_card_table.jpg").exists(),
    reason="Sample images not available (run from full checkout with test assets)",
)


@pytest.fixture(autouse=True)
def isolate_settings_from_dotenv(monkeypatch: pytest.MonkeyPatch) -> None:
    """Prevent .env file values from leaking into unit tests.

    pydantic_settings reads .env files as a fallback when env vars are absent,
    so monkeypatch.delenv alone is insufficient. Setting all known settings vars
    here ensures env vars take priority, matching field defaults from settings.py.
    Individual tests may override specific vars with monkeypatch.setenv.
    """
    defaults: dict[str, str] = {
        # LLM provider selection
        "MTG_SCANNER_LLM_PROVIDER": "",
        "MTG_SCANNER_LLM_API_KEY": "",
        "MTG_SCANNER_LLM_MODEL": "",
        "MTG_SCANNER_LLM_BASE_URL": "",
        "MTG_SCANNER_LLM_TIMEOUT_SECONDS": "30",
        "MTG_SCANNER_LLM_RESPONSE_MODE": "json_schema",
        # Legacy provider
        "MTG_SCANNER_RECOGNIZER_PROVIDER": "",
        # OpenAI
        "OPENAI_API_KEY": "",
        "OPENAI_MODEL": "",
        "OPENAI_BASE_URL": "",
        # Moonshot
        "MOONSHOT_API_KEY": "",
        "MOONSHOT_MODEL": "",
        "MOONSHOT_BASE_URL": "",
        # Anthropic
        "ANTHROPIC_API_KEY": "",
        "ANTHROPIC_MODEL": "",
        "ANTHROPIC_BASE_URL": "",
        # Feature flags
        "MTG_SCANNER_ENABLE_MULTI_CARD": "true",
        "MTG_SCANNER_ENABLE_MTG_VALIDATION": "true",
        "MTG_SCANNER_ENABLE_CK_PRICES": "false",
        "MTG_SCANNER_ENABLE_LLM_CORRECTION": "true",
        # Misc settings
        "MTG_SCANNER_MAX_CONCURRENT_RECOGNITIONS": "4",
        "MTG_SCANNER_CORRECTION_PROMPT_VERSION": "card-correction.md",
        "MTG_SCANNER_PRICING_REFRESH_INTERVAL_HOURS": "0",
        "MTG_SCANNER_ADMIN_TOKEN": "",
        "MTG_SCANNER_LOG_LEVEL": "INFO",
    }
    for env_var, value in defaults.items():
        monkeypatch.setenv(env_var, value)
