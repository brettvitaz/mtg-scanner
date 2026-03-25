#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .venv/bin/activate
uvicorn app.main:app --app-dir services/api --reload
