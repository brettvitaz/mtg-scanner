#!/usr/bin/env python3
"""Run local recognition evals against sample images and ground truth."""

from __future__ import annotations

import json
import mimetypes
from dataclasses import asdict, dataclass
from pathlib import Path

from app.models.recognition import RecognitionUploadMetadata
from app.services.recognizer import get_recognition_service

REPO_ROOT = Path(__file__).resolve().parents[1]
SAMPLES_DIR = REPO_ROOT / "samples"
FIXTURES_DIR = SAMPLES_DIR / "fixtures"
GROUND_TRUTH_DIR = SAMPLES_DIR / "ground-truth"
RESULTS_DIR = REPO_ROOT / "evals" / "results"


@dataclass
class CaseResult:
    fixture: str
    provider: str | None
    model: str | None
    expected_cards: int
    actual_cards: int
    matched_title_count: int
    matched_edition_count: int
    matched_collector_number_count: int
    passed: bool


def main() -> int:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    service = get_recognition_service()

    case_results: list[CaseResult] = []
    fixture_paths = sorted(
        p for p in FIXTURES_DIR.iterdir() if p.is_file() and not p.name.startswith(".")
    )
    if not fixture_paths:
        print("No fixture images found in samples/fixtures")
        return 1

    for fixture_path in fixture_paths:
        gt_path = GROUND_TRUTH_DIR / f"{fixture_path.stem}.json"
        if not gt_path.exists():
            print(f"Skipping {fixture_path.name}: missing ground truth {gt_path.name}")
            continue

        metadata = RecognitionUploadMetadata(
            filename=fixture_path.name,
            content_type=mimetypes.guess_type(fixture_path.name)[0] or "image/jpeg",
            prompt_version="card-recognition.md",
        )
        response, enriched_metadata, _ = service.recognize(
            image_bytes=fixture_path.read_bytes(),
            metadata=metadata,
        )
        expected = json.loads(gt_path.read_text())
        case_results.append(compare_case(fixture_path.name, enriched_metadata, expected, response.model_dump()))

    summary = {
        "cases": [asdict(case) for case in case_results],
        "total_cases": len(case_results),
        "passed_cases": sum(1 for case in case_results if case.passed),
    }
    out_path = RESULTS_DIR / "latest.json"
    out_path.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0 if summary["total_cases"] and summary["total_cases"] == summary["passed_cases"] else 2


def compare_case(fixture: str, metadata: RecognitionUploadMetadata, expected: dict, actual: dict) -> CaseResult:
    expected_cards = expected.get("cards", [])
    actual_cards = actual.get("cards", [])

    matched_title_count = count_matches(expected_cards, actual_cards, "title")
    matched_edition_count = count_matches(expected_cards, actual_cards, "edition")
    matched_collector_number_count = count_matches(expected_cards, actual_cards, "collector_number")

    passed = (
        len(expected_cards) == len(actual_cards)
        and matched_title_count == len(expected_cards)
        and matched_edition_count == len(expected_cards)
        and matched_collector_number_count == len(expected_cards)
    )

    return CaseResult(
        fixture=fixture,
        provider=metadata.provider,
        model=metadata.model,
        expected_cards=len(expected_cards),
        actual_cards=len(actual_cards),
        matched_title_count=matched_title_count,
        matched_edition_count=matched_edition_count,
        matched_collector_number_count=matched_collector_number_count,
        passed=passed,
    )


def count_matches(expected_cards: list[dict], actual_cards: list[dict], field: str) -> int:
    actual_values = [card.get(field) for card in actual_cards]
    expected_values = [card.get(field) for card in expected_cards]
    return sum(1 for value in expected_values if value in actual_values)


if __name__ == "__main__":
    raise SystemExit(main())
