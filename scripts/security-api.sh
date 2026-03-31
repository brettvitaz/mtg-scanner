#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .venv/bin/activate

echo "Running bandit security scan..."
bandit -c services/api/pyproject.toml -r services/api/app/ --confidence-level high
echo "bandit passed."

echo ""
echo "Running uv dependency audit..."
uv audit --directory services/api
echo "uv audit passed."
