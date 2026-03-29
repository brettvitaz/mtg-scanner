#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v swiftlint &>/dev/null; then
  echo "Error: swiftlint not installed. Install with: brew install swiftlint"
  exit 1
fi

echo "Running SwiftLint..."
swiftlint lint --strict
echo "SwiftLint passed."
