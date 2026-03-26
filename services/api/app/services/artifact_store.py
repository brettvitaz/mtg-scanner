import json
import mimetypes
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

from app.models.recognition import RecognitionResponse, RecognitionUploadMetadata
from app.settings import get_settings


@dataclass(slots=True)
class StoredRecognitionArtifacts:
    directory: Path
    image_path: Path
    response_path: Path
    metadata_path: Path
    crops_dir: Path | None = None


class LocalArtifactStore:
    def __init__(self, base_dir: Path) -> None:
        self._base_dir = base_dir

    def save_recognition(
        self,
        image_bytes: bytes,
        metadata: RecognitionUploadMetadata,
        response: RecognitionResponse,
        detection_result = None,  # type: ignore[no-untyped-def]
    ) -> StoredRecognitionArtifacts:
        from app.services.card_detector import DetectionResult

        run_id = self._make_run_id()
        artifact_dir = self._base_dir / "recognitions" / run_id
        artifact_dir.mkdir(parents=True, exist_ok=False)

        image_path = artifact_dir / self._make_image_name(metadata)
        image_path.write_bytes(image_bytes)

        response_path = artifact_dir / "response.json"
        response_path.write_text(response.model_dump_json(indent=2) + "\n")

        # Build metadata dict
        metadata_dict: dict = {
            "filename": metadata.filename,
            "content_type": metadata.content_type,
            "prompt_version": metadata.prompt_version,
            "provider": metadata.provider,
            "model": metadata.model,
            "saved_at": datetime.now(UTC).isoformat(),
        }

        # Save detection result if available
        crops_dir: Path | None = None
        if detection_result is not None and isinstance(detection_result, DetectionResult):
            metadata_dict["detected_cards"] = detection_result.count
            metadata_dict["original_shape"] = detection_result.original_shape

            if detection_result.regions:
                # Save individual crops first so metadata can reference concrete files.
                crops_dir = artifact_dir / "crops"
                crops_dir.mkdir(exist_ok=True)

                detector = None
                region_entries: list[dict] = []
                crop_files: list[str] = []

                for i, region in enumerate(detection_result.regions):
                    if detector is None:
                        from app.services.card_detector import CardDetector
                        detector = CardDetector()

                    crop_bytes, _ = detector.crop_region(image_bytes, region)
                    crop_filename = f"card-{i}.jpg"
                    crop_path = crops_dir / crop_filename
                    crop_path.write_bytes(crop_bytes)
                    crop_files.append(crop_filename)

                    region_entries.append(
                        {
                            "x": region.x,
                            "y": region.y,
                            "width": region.width,
                            "height": region.height,
                            "confidence": region.confidence,
                            "crop_path": f"crops/{crop_filename}",
                        }
                    )

                metadata_dict["regions"] = region_entries
                metadata_dict["crop_files"] = crop_files

        metadata_path = artifact_dir / "metadata.json"
        metadata_path.write_text(json.dumps(metadata_dict, indent=2) + "\n")

        return StoredRecognitionArtifacts(
            directory=artifact_dir,
            image_path=image_path,
            response_path=response_path,
            metadata_path=metadata_path,
            crops_dir=crops_dir,
        )

    def _make_run_id(self) -> str:
        timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S")
        return f"{timestamp}-{uuid4().hex[:8]}"

    def _make_image_name(self, metadata: RecognitionUploadMetadata) -> str:
        source = Path(metadata.filename)
        suffix = source.suffix or mimetypes.guess_extension(metadata.content_type) or ".bin"
        return f"upload{suffix}"


def get_artifacts_base_dir() -> Path:
    settings = get_settings()
    if settings.mtg_scanner_artifacts_dir:
        return Path(settings.mtg_scanner_artifacts_dir).expanduser()

    return Path(__file__).resolve().parents[3] / ".artifacts"


def get_artifact_store() -> LocalArtifactStore:
    return LocalArtifactStore(get_artifacts_base_dir())
