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
