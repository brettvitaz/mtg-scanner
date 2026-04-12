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
    """Prevent .env file values from leaking into unit tests."""
    monkeypatch.setitem(Settings.model_config, "env_file", ())
