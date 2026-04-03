#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEMPLATES_DIR="docs/work-efforts/templates"
EFFORTS_DIR="docs/work-efforts"

usage() {
  echo "Usage: $0 <slug>"
  echo ""
  echo "Creates a new work-effort folder with template files."
  echo ""
  echo "  slug   Kebab-case name for the effort (e.g., fix-crop-rotation)"
  echo ""
  echo "Examples:"
  echo "  $0 fix-crop-rotation"
  echo "  $0 add-binder-detection"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

slug="$1"

# Validate kebab-case: lowercase letters, numbers, hyphens between words
if [[ ! "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Error: slug must be kebab-case (lowercase letters, numbers, hyphens)." >&2
  echo "  Got: $slug" >&2
  echo "  Example: fix-crop-rotation" >&2
  exit 1
fi

date_prefix=$(date +%Y-%m-%d)
effort_dir="${EFFORTS_DIR}/${date_prefix}-${slug}"

if [[ -d "$effort_dir" ]]; then
  echo "Error: work effort already exists: $effort_dir" >&2
  exit 1
fi

# Also check for same slug with a different date
existing=$(find "$EFFORTS_DIR" -maxdepth 1 -type d -name "*-${slug}" 2>/dev/null | head -1)
if [[ -n "$existing" ]]; then
  echo "Error: a work effort with slug '${slug}' already exists: $existing" >&2
  exit 1
fi

if [[ ! -d "$TEMPLATES_DIR" ]]; then
  echo "Error: templates directory not found: $TEMPLATES_DIR" >&2
  exit 1
fi

mkdir -p "$effort_dir"
cp "$TEMPLATES_DIR"/request.md "$effort_dir/"
cp "$TEMPLATES_DIR"/plan.md "$effort_dir/"
cp "$TEMPLATES_DIR"/log.md "$effort_dir/"
cp "$TEMPLATES_DIR"/review.md "$effort_dir/"

# Strip the example entry from log.md (everything after the EXAMPLE marker)
sed -i '' '/^<!-- EXAMPLE/,$d' "$effort_dir/log.md"

echo "Created work effort: $effort_dir"
echo ""
echo "Next step: fill out $effort_dir/request.md"
