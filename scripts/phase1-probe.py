#!/usr/bin/env python3
"""Prepare and launch the isolated Phase 1 diagnostic app without logging credentials."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path

from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "com.brettvitaz.mtgscanner.feasibility"
SAMPLES = {
    "ordinary.jpg": "samples/fixtures/4ed-154.jpg",
    "list.jpg": "samples/fixtures/the-list_pca-050.jpg",
    "split.jpg": "apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CropEvaluationFixtures/"
    "labeled-outputs/under-crop/auto-under-crop-wear-tear-box.jpg",
    "foil-evidence.jpg": "apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/CropEvaluationFixtures/"
    "labeled-outputs/good/auto-good-kruphix-god-of-horizons.jpg",
}


def values(env_file: Path | None) -> dict[str, str]:
    file_values = dotenv_values(env_file) if env_file else {}
    return {key: value for key, value in {**file_values, **os.environ}.items() if value is not None}


def prepare(directory: Path, config: dict[str, str]) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "samples").mkdir(exist_ok=True)
    providers = []
    defaults = {"openai": "gpt-4.1-mini", "moonshot": "kimi-k2.5", "anthropic": "claude-sonnet-4-6"}
    for kind, default in defaults.items():
        providers.append({"kind": kind, "model": config.get(kind.upper() + "_MODEL", default), "mode": "schema"})
    (directory / "config.json").write_text(json.dumps({"providers": providers, "samples": list(SAMPLES)}, indent=2))
    for target, source in SAMPLES.items():
        shutil.copyfile(ROOT / source, directory / "samples" / target)
    for name in ["card-recognition.md", "card-correction.md"]:
        shutil.copyfile(ROOT / "prompts" / name, directory / name)
    shutil.copyfile(ROOT / "packages/schemas/v1/llm-output.schema.json", directory / "llm-output.schema.json")
    shutil.copyfile(ROOT / "services/api/data/pricing/model_prices.json", directory / "model_prices.json")
    print(f"Prepared credential-free inputs: {directory}")


def launch(device: str, config: dict[str, str], probes: list[str]) -> None:
    env = os.environ.copy()
    for key in ["OPENAI_API_KEY", "MOONSHOT_API_KEY", "ANTHROPIC_API_KEY"]:
        if config.get(key):
            env["DEVICECTL_CHILD_" + key] = config[key]
    command = ["xcrun", "devicectl", "device", "process", "launch", "--device", device,
               "--terminate-existing", BUNDLE, "--migration-probe"]
    command.extend("--probe-" + probe for probe in probes)
    # devicectl inherits secrets through the environment, never command-line JSON or files.
    result = subprocess.run(command, env=env, capture_output=True, check=False)
    if result.returncode:
        raise SystemExit(f"Device launch failed (exit {result.returncode}); inspect device connection/signing.")
    print(f"Launched isolated diagnostic app: {', '.join(probes)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "launch"])
    parser.add_argument("--env-file", type=Path)
    parser.add_argument("--directory", type=Path, default=ROOT / "tmp/phase1-inputs")
    parser.add_argument("--device")
    parser.add_argument("--probes", nargs="+", choices=["catalog", "prices", "recognition", "correction", "cancel-catalog"],
                        default=["catalog", "prices", "recognition"])
    args = parser.parse_args()
    if args.action == "prepare":
        prepare(args.directory, values(args.env_file))
    elif args.device:
        launch(args.device, values(args.env_file), args.probes)
    else:
        parser.error("launch requires --device")


if __name__ == "__main__":
    main()
