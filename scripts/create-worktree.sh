#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_NAME="$(basename "$REPO_ROOT")"

to_kebab() {
	echo "$1" |
		tr '[:upper:]' '[:lower:]' |
		sed 's/[^a-z0-9]/-/g' |
		sed 's/-\+/-/g' |
		sed 's/^-//;s/-$//'
}

usage() {
	echo "Usage: $0 <worktree-name>"
	echo ""
	echo "Creates a new git worktree with a matching branch."
	echo ""
	echo "  worktree-name   Name for the branch and worktree (converted to kebab-case)"
	echo ""
	echo "The worktree is created at ../${REPO_NAME}-worktrees/<worktree-name>"
	echo ""
	echo "Examples:"
	echo "  $0 fix-crop-rotation"
	echo "  $0 \"Add Binder Detection\""
	echo "  $0 \"Fix_Crop_Rotation_Bug\""
	exit 1
}

if [[ $# -lt 1 ]]; then
	usage
fi

name="$(to_kebab "$1")"

if [[ -z "$name" ]]; then
	echo "Error: could not generate a valid kebab-case name from: $1" >&2
	exit 1
fi

WORKTREES_DIR="../${REPO_NAME}-worktrees"
WORKTREE_PATH="${WORKTREES_DIR}/${name}"

if [[ -d "$WORKTREE_PATH" ]]; then
	echo "Error: worktree already exists: $WORKTREE_PATH" >&2
	exit 1
fi

echo "Creating worktree: $WORKTREE_PATH"
echo "Branch: $name"

git worktree add "$WORKTREE_PATH" -b "$name"

# Copy .env files from main repo to worktree
env_files=()
while IFS= read -r -d '' file; do
	env_files+=("$file")
done < <(find "$REPO_ROOT" -maxdepth 3 -name ".env*" -type f -print0)

if [[ ${#env_files[@]} -gt 0 ]]; then
	for env_file in "${env_files[@]}"; do
		relative="${env_file#$REPO_ROOT/}"
		target="${WORKTREE_PATH}/${relative}"
		target_dir="$(dirname "$target")"
		mkdir -p "$target_dir"
		cp "$env_file" "$target"
		echo "Copied: $relative"
	done
fi

# Post-create setup
post_create() {
	local wt_dir="$1"
	local effort_name="$2"

	echo ""
	echo "Running post-create setup..."

	cd "$wt_dir"

	echo "Creating work effort..."
	./scripts/new-work-effort.sh "$effort_name"

	echo "Bootstrapping API..."
	make api-bootstrap && make api-import-ck-prices && make api-update-mtgjson

	echo ""
	echo "Worktree ready: $wt_dir"
}

post_create "$(cd "$WORKTREE_PATH" && pwd)" "$name"
