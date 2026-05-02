#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .venv/bin/activate
PYTHONPATH=services/api python evals/run_eval.py "$@"
