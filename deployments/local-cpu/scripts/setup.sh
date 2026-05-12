#!/usr/bin/env bash
# setup.sh — One-time setup for the local-cpu deployment.
# Run from the deployments/local-cpu directory.
# Requires: Docker with Compose v2, internet access for the initial model pull.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

log()  { printf '\033[1;32m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[setup]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

# ── Prerequisites ────────────────────────────────────────────────────────────
command -v docker  >/dev/null 2>&1 || die "Docker not found. Install Docker Desktop or Docker Engine."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 not found. Update Docker."

log "Docker $(docker --version | cut -d' ' -f3 | tr -d ',')"

# ── Create workspace directory ───────────────────────────────────────────────
mkdir -p workspace
log "Workspace directory ready at ./workspace"

# ── Build the oh-my-pi image ─────────────────────────────────────────────────
log "Building oh-my-pi image (requires internet access)..."
docker compose build omp

# ── Start Ollama ─────────────────────────────────────────────────────────────
log "Starting Ollama container (CPU-only mode)..."
docker compose up -d ollama

log "Waiting for Ollama to pass health check..."
until docker compose exec ollama curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; do
    printf '.'
    sleep 3
done
echo ""
log "Ollama is ready."

# ── Pull and register the model ───────────────────────────────────────────────
bash "$SCRIPT_DIR/pull-model.sh"

log ""
log "Setup complete."
log "Start oh-my-pi with:  bash scripts/start-omp.sh"
log "                  or: docker compose run --rm --profile interactive omp"
