#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .venv/bin/activate
echo "Running mypy..."
mypy --config-file services/api/pyproject.toml services/api/app/
echo "mypy passed."
