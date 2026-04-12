import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.settings import Settings

SAMPLES_DIR = Path(__file__).resolve().parents[3] / "samples" / "test"
ARTIFACTS_DIR = SAMPLES_DIR / "artifacts"

requires_sample_images = pytest.mark.skipif(
    not (SAMPLES_DIR / "IMG_1611.png").exists()
    or not (ARTIFACTS_DIR / "two_card_table.jpg").exists(),
    reason="Sample images not available (run from full checkout with test assets)",
)


@pytest.fixture(autouse=True)
def isolate_settings_from_dotenv(monkeypatch: pytest.MonkeyPatch) -> None:
    """Prevent process and .env configuration from leaking into unit tests."""
    monkeypatch.setitem(Settings.model_config, "env_file", ())
    for env_var in (
        "MTG_SCANNER_RECOGNIZER_PROVIDER",
        "MTG_SCANNER_LLM_PROVIDER",
        "MTG_SCANNER_LLM_API_KEY",
        "MTG_SCANNER_LLM_MODEL",
        "MTG_SCANNER_LLM_BASE_URL",
        "MTG_SCANNER_LLM_TIMEOUT_SECONDS",
        "MTG_SCANNER_LLM_RESPONSE_MODE",
        "OPENAI_API_KEY",
        "OPENAI_MODEL",
        "OPENAI_BASE_URL",
        "MOONSHOT_API_KEY",
        "MOONSHOT_MODEL",
        "MOONSHOT_BASE_URL",
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_MODEL",
        "ANTHROPIC_BASE_URL",
    ):
        monkeypatch.delenv(env_var, raising=False)
