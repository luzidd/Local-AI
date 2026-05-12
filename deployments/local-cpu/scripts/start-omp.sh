#!/usr/bin/env bash
# start-omp.sh — Launch oh-my-pi in the Docker container interactively.
#
# Usage:
#   bash scripts/start-omp.sh              # open interactive TUI
#   bash scripts/start-omp.sh -p "prompt"  # non-interactive one-shot
#   bash scripts/start-omp.sh --help       # show omp CLI help
#
# WORKSPACE_DIR: set this env var to mount a different directory.
#   WORKSPACE_DIR=/path/to/myproject bash scripts/start-omp.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

die() { printf '\033[1;31m[omp]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

# Ensure Ollama is up
docker compose ps ollama 2>/dev/null | grep -q "running" \
    || die "Ollama is not running. Start it with: docker compose up -d ollama"

# Pass all arguments through to omp inside the container
exec docker compose run --rm \
    --profile interactive \
    -e WORKSPACE_DIR="${WORKSPACE_DIR:-}" \
    omp "$@"
