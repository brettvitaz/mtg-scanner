#!/usr/bin/env python3
"""Run local recognition evals against sample images and ground truth."""

from __future__ import annotations

import argparse
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
    prompt_version: str
    expected_cards: int
    actual_cards: int
    matched_title_count: int
    matched_edition_count: int
    matched_collector_number_count: int
    matched_foil_count: int
    matched_border_color_count: int
    passed: bool


def main() -> int:
    parser = argparse.ArgumentParser(description="Run MTG card recognition evals")
    parser.add_argument(
        "--prompt-version",
        default="card-recognition.md",
        help="Prompt file to use (relative to prompts/, default: card-recognition.md)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Save per-fixture actual responses alongside results",
    )
    args = parser.parse_args()

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

        expected = json.loads(gt_path.read_text())
        metadata = RecognitionUploadMetadata(
            filename=fixture_path.name,
            content_type=mimetypes.guess_type(fixture_path.name)[0] or "image/jpeg",
            prompt_version=args.prompt_version,
        )
        skip_detection = bool(expected.get("skip_detection", False))
        response, enriched_metadata, _detection, _validation, _usage = service.recognize(
            image_bytes=fixture_path.read_bytes(),
            metadata=metadata,
            skip_detection=skip_detection,
        )
        actual = response.model_dump()
        if args.verbose:
            actual_path = RESULTS_DIR / f"{fixture_path.stem}.actual.json"
            actual_path.write_text(json.dumps(actual, indent=2) + "\n")
        case_results.append(
            compare_case(fixture_path.name, args.prompt_version, enriched_metadata, expected, actual)
        )

    summary = {
        "prompt_version": args.prompt_version,
        "cases": [asdict(case) for case in case_results],
        "total_cases": len(case_results),
        "passed_cases": sum(1 for case in case_results if case.passed),
    }
    out_path = RESULTS_DIR / "latest.json"
    out_path.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0 if summary["total_cases"] and summary["total_cases"] == summary["passed_cases"] else 2


DEFAULT_PASS_CRITERIA = {"title", "edition", "collector_number"}


def compare_case(
    fixture: str,
    prompt_version: str,
    metadata: RecognitionUploadMetadata,
    expected: dict,
    actual: dict,
) -> CaseResult:
    expected_cards = expected.get("cards", [])
    actual_cards = actual.get("cards", [])
    pass_criteria = set(expected.get("pass_criteria", DEFAULT_PASS_CRITERIA))

    matched_title_count = count_matches(expected_cards, actual_cards, "title")
    matched_edition_count = count_matches(expected_cards, actual_cards, "edition")
    matched_collector_number_count = count_matches(expected_cards, actual_cards, "collector_number")
    matched_foil_count = count_matches(expected_cards, actual_cards, "foil_type")
    matched_border_color_count = count_matches(expected_cards, actual_cards, "border_color")

    criteria_counts = {
        "title": matched_title_count,
        "edition": matched_edition_count,
        "collector_number": matched_collector_number_count,
    }
    passed = len(expected_cards) == len(actual_cards) and all(
        criteria_counts[field] == len(expected_cards)
        for field in pass_criteria
        if field in criteria_counts
    )

    return CaseResult(
        fixture=fixture,
        provider=metadata.provider,
        model=metadata.model,
        prompt_version=prompt_version,
        expected_cards=len(expected_cards),
        actual_cards=len(actual_cards),
        matched_title_count=matched_title_count,
        matched_edition_count=matched_edition_count,
        matched_collector_number_count=matched_collector_number_count,
        matched_foil_count=matched_foil_count,
        matched_border_color_count=matched_border_color_count,
        passed=passed,
    )


def _normalize_field(field: str, value: object) -> object:
    if not isinstance(value, str):
        return value
    if field == "collector_number":
        # Strip leading zeros from numeric prefix to match validation normalization
        stripped = value.lstrip("0")
        return stripped if stripped else "0"
    if field == "edition":
        return value.strip().lower()
    return value


def count_matches(expected_cards: list[dict], actual_cards: list[dict], field: str) -> int:
    actual_values = [_normalize_field(field, card.get(field)) for card in actual_cards]
    expected_values = [_normalize_field(field, card.get(field)) for card in expected_cards]
    return sum(1 for value in expected_values if value in actual_values)


if __name__ == "__main__":
    raise SystemExit(main())
