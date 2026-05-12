#!/usr/bin/env bash
# pull-model.sh — Pull gemma4:26b from Ollama registry and register the
# tuned model variant (gemma4-local) using the Modelfile.
#
# Re-runnable: safe to call again after the initial setup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

log()  { printf '\033[1;32m[model]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[model]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

docker compose ps ollama | grep -q "running" || die "Ollama container is not running. Run 'docker compose up -d ollama' first."

# ── Pull base model (~18 GB, Q4_K_M) ────────────────────────────────────────
log "Pulling gemma4:26b (Mixture of Experts, Q4 ~18 GB)..."
log "This is a one-time download. Subsequent starts use the local cache."
docker compose exec ollama ollama pull gemma4:26b

# ── Register the tuned model variant ─────────────────────────────────────────
log "Registering gemma4-local model from Modelfile..."
# Copy Modelfile into the container (already mounted read-only at /tmp/Modelfile)
docker compose exec ollama ollama create gemma4-local -f /tmp/Modelfile

log "Model registered. Verify with:"
log "  docker compose exec ollama ollama list"

# ── Optional: Q8 variant ──────────────────────────────────────────────────────
# Uncomment the block below if you want Q8 quantization.
# WARNING: Q8 requires ~32 GB of RAM for model weights alone.
# With a 32 GB host you will likely OOM. Only use Q8 with ≥48 GB RAM.
#
# log "Pulling gemma4:26b-q8_0 (~32 GB)..."
# docker compose exec ollama ollama pull gemma4:26b-q8_0
