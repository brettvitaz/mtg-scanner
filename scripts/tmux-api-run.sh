#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMUX_SESSION="mtg-api"

# If session already exists, attach to it
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  exec tmux attach-session -t "$TMUX_SESSION"
fi

# Run setup, then start the API server
tmux new-session -d -s "$TMUX_SESSION" -c "$SCRIPT_DIR" "make api-setup && make api-run"
tmux attach-session -t "$TMUX_SESSION"
