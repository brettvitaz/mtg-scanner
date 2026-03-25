#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -e ./services/api[dev]
echo "API environment ready. Activate with: source .venv/bin/activate"
