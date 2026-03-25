import json
import mimetypes
import os
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

from app.models.recognition import RecognitionResponse, RecognitionUploadMetadata


@dataclass(slots=True)
class StoredRecognitionArtifacts:
    directory: Path
    image_path: Path
    response_path: Path
    metadata_path: Path


class LocalArtifactStore:
    def __init__(self, base_dir: Path) -> None:
        self._base_dir = base_dir

    def save_recognition(
        self,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
        response: RecognitionResponse,
    ) -> StoredRecognitionArtifacts:
        run_id = self._make_run_id()
        artifact_dir = self._base_dir / "recognitions" / run_id
        artifact_dir.mkdir(parents=True, exist_ok=False)

        image_path = artifact_dir / self._make_image_name(metadata)
        image_path.write_bytes(image_bytes)

        response_path = artifact_dir / "response.json"
        response_path.write_text(response.model_dump_json(indent=2) + "\n")

        metadata_path = artifact_dir / "metadata.json"
        metadata_path.write_text(
            json.dumps(
                {
                    "filename": metadata.filename,
                    "content_type": metadata.content_type,
                    "prompt_version": metadata.prompt_version,
                    "provider": metadata.provider,
                    "model": metadata.model,
                    "saved_at": datetime.now(UTC).isoformat(),
                },
                indent=2,
            )
            + "\n"
        )

        return StoredRecognitionArtifacts(
            directory=artifact_dir,
            image_path=image_path,
            response_path=response_path,
            metadata_path=metadata_path,
        )

    def _make_run_id(self) -> str:
        timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S")
        return f"{timestamp}-{uuid4().hex[:8]}"

    def _make_image_name(self, metadata: RecognitionUploadMetadata) -> str:
        source = Path(metadata.filename)
        suffix = source.suffix or mimetypes.guess_extension(metadata.content_type) or ".bin"
        return f"upload{suffix}"


def get_artifacts_base_dir() -> Path:
    configured_dir = os.environ.get("MTG_SCANNER_ARTIFACTS_DIR")
    if configured_dir:
        return Path(configured_dir).expanduser()

    return Path(__file__).resolve().parents[3] / ".artifacts"


def get_artifact_store() -> LocalArtifactStore:
    return LocalArtifactStore(get_artifacts_base_dir())
