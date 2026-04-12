#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v uv &>/dev/null; then
	echo "Error: uv is not installed. Install with: brew install uv" >&2
	exit 1
fi

uv venv --clear .venv
uv pip install -e "./services/api[dev]"
echo "API environment ready. Activate with: source .venv/bin/activate"
