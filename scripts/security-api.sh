#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .venv/bin/activate

echo "Running bandit security scan..."
bandit -c services/api/pyproject.toml -r services/api/app/ --confidence-level high
echo "bandit passed."

echo ""
echo "Running pip-audit dependency scan..."
pip-audit
echo "pip-audit passed."
