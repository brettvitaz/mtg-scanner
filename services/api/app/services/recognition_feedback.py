import base64
import errno
import json
import os
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from app.models.recognition_feedback import RecognitionFeedbackRequest


def save_feedback(event: RecognitionFeedbackRequest, base_dir: Path) -> bool:
    """Atomically publish a complete event. Return True for an acknowledged duplicate."""
    root = base_dir / "recognition-feedback"
    root.mkdir(parents=True, exist_ok=True)
    destination = root / str(event.event_id)
    if destination.is_dir():
        return True
    with tempfile.TemporaryDirectory(prefix=".pending-", dir=root) as staging:
        directory = Path(staging) / "event"
        directory.mkdir()
        (directory / "scan.jpg").write_bytes(base64.b64decode(event.scan_jpeg))
        metadata = event.model_dump(mode="json", exclude={"scan_jpeg"}, exclude_none=True)
        metadata["saved_at"] = datetime.now(UTC).isoformat()
        (directory / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
        try:
            os.rename(directory, destination)
        except OSError as error:
            if error.errno in (errno.EEXIST, errno.ENOTEMPTY) and destination.is_dir():
                return True
            raise
    return False
