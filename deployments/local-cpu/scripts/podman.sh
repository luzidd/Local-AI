#!/usr/bin/env bash
# podman.sh — Podman equivalent of compose.yaml using bind-mounted paths.
#
# Usage:
#   bash scripts/podman.sh setup        — build image, create dirs, start Ollama, pull model
#   bash scripts/podman.sh pull-model   — (re)pull and register gemma4-local
#   bash scripts/podman.sh start [args] — launch omp interactively (starts Ollama if stopped)
#   bash scripts/podman.sh stop         — stop the Ollama container
#   bash scripts/podman.sh logs         — tail Ollama logs
#
# Environment:
#   OLLAMA_NUM_THREADS  — CPU threads for inference (default: 8)
#   WORKSPACE_DIR       — host path mounted as /workspace in omp (default: ./workspace)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

log()  { printf '\033[1;32m[podman]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[podman]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[podman]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

# ── Configuration ─────────────────────────────────────────────────────────────
# Bind-mount directories on the host (replaces named volumes)
OLLAMA_DATA="$DEPLOY_DIR/data/ollama"   # → /root/.ollama inside container
OMP_DATA="$DEPLOY_DIR/data/omp"         # → /root/.omp   inside container
WORKSPACE="${WORKSPACE_DIR:-$DEPLOY_DIR/workspace}"

OLLAMA_THREADS="${OLLAMA_NUM_THREADS:-8}"
OLLAMA_IMAGE="docker.io/ollama/ollama:latest"
OMP_IMAGE="localhost/omp:local"
OLLAMA_CONTAINER="ollama"
NETWORK="local-ai"

# ── Helpers ───────────────────────────────────────────────────────────────────
require_podman() {
    command -v podman >/dev/null 2>&1 || die "podman not found. Install with: sudo dnf install podman"
}

ollama_running() {
    podman container inspect "$OLLAMA_CONTAINER" --format '{{.State.Running}}' 2>/dev/null | grep -q "true"
}

ollama_healthy() {
    # Check from the host against the exposed port — the ollama image does not
    # include curl, so exec-ing into the container is not an option.
    curl -sf http://localhost:11434/api/tags >/dev/null 2>&1
}

wait_healthy() {
    log "Waiting for Ollama to be ready..."
    local attempts=0
    until ollama_healthy; do
        printf '.'
        sleep 3
        attempts=$((attempts + 1))
        [[ $attempts -gt 30 ]] && echo "" && die "Ollama did not become ready in time."
    done
    echo ""
    log "Ollama is ready."
}

ensure_network() {
    podman network exists "$NETWORK" 2>/dev/null || {
        log "Creating network: $NETWORK"
        podman network create "$NETWORK"
    }
}

ensure_ollama_running() {
    if ! ollama_running; then
        log "Ollama is not running — starting it..."
        cmd_start_ollama
        wait_healthy
    fi
}

# ── Commands ──────────────────────────────────────────────────────────────────
cmd_setup() {
    require_podman

    log "Creating bind-mount directories..."
    mkdir -p "$OLLAMA_DATA" "$OMP_DATA/agent" "$WORKSPACE"
    cp "$DEPLOY_DIR/config/models.yml" "$OMP_DATA/agent/models.yml"
    cp "$DEPLOY_DIR/config/config.yml"  "$OMP_DATA/agent/config.yml"

    ensure_network

    log "Building oh-my-pi image..."
    podman build -t "$OMP_IMAGE" -f "$DEPLOY_DIR/Dockerfile.omp" "$DEPLOY_DIR"

    log "Pulling Ollama image..."
    podman pull "$OLLAMA_IMAGE"

    cmd_start_ollama
    wait_healthy
    cmd_pull_model

    log ""
    log "Setup complete."
    log "Launch omp with: bash scripts/podman.sh start"
}

cmd_start_ollama() {
    require_podman
    ensure_network

    if ollama_running; then
        log "Ollama is already running."
        return
    fi

    # Remove a stopped container of the same name if one exists
    podman container exists "$OLLAMA_CONTAINER" 2>/dev/null \
        && podman rm "$OLLAMA_CONTAINER" >/dev/null

    log "Starting Ollama (CPU-only)..."
    podman run -d \
        --name "$OLLAMA_CONTAINER" \
        --network "$NETWORK" \
        --restart unless-stopped \
        -p 11434:11434 \
        -v "$OLLAMA_DATA":/root/.ollama:Z \
        -v "$DEPLOY_DIR/config/Modelfile":/tmp/Modelfile:ro,Z \
        -e OLLAMA_NUM_THREADS="$OLLAMA_THREADS" \
        -e OLLAMA_FLASH_ATTENTION=1 \
        -e OLLAMA_MAX_LOADED_MODELS=1 \
        -e OLLAMA_KEEP_ALIVE=30m \
        -e CUDA_VISIBLE_DEVICES="" \
        -e OLLAMA_GPU_OVERHEAD=0 \
        "$OLLAMA_IMAGE"
    log "Ollama container started."
}

cmd_pull_model() {
    require_podman
    ensure_ollama_running

    log "Pulling gemma4:26b (~18 GB Q4 — first run only)..."
    podman exec "$OLLAMA_CONTAINER" ollama pull gemma4:26b

    log "Registering gemma4-local from Modelfile..."
    podman exec "$OLLAMA_CONTAINER" ollama create gemma4-local -f /tmp/Modelfile

    log "Model registered. Verify with: podman exec $OLLAMA_CONTAINER ollama list"
}

cmd_start() {
    require_podman
    ensure_ollama_running

    # Copy config files into the data dir before each run.
    # Podman does not reliably apply file mounts that sit inside a path already
    # covered by a parent directory bind mount — the parent mount wins and the
    # file mounts are silently ignored, leaving omp with no provider config.
    # Copying avoids nested mounts entirely while still reflecting any edits
    # made to the source configs on every launch.
    mkdir -p "$OMP_DATA/agent"
    cp "$DEPLOY_DIR/config/models.yml" "$OMP_DATA/agent/models.yml"
    cp "$DEPLOY_DIR/config/config.yml"  "$OMP_DATA/agent/config.yml"

    log "Launching oh-my-pi..."
    # Single bind mount — no nested file mounts needed.
    # :Z relabels for SELinux (no-op on non-SELinux systems).
    #
    # --tools restricts the built-in tool set sent to the model on every
    # request. Each tool schema costs tokens; the full set consumes ~16K.
    # Remove tools from this list if you need them, or pass --no-tools
    # to omp directly for a read-only session.
    # Full tool name reference: https://github.com/can1357/oh-my-pi#built-in-tool-names---tools
    local DEFAULT_TOOLS="bash,edit,find,grep,ast_grep,ast_edit,read,write,fetch,web_search,task,poll,todo_write,lsp,ask,calc"
    podman run --rm -it \
        --network "$NETWORK" \
        -v "$OMP_DATA":/root/.omp:Z \
        -v "$WORKSPACE":/workspace:Z \
        -w /workspace \
        -e OLLAMA_HOST="http://$OLLAMA_CONTAINER:11434" \
        "$OMP_IMAGE" --tools "$DEFAULT_TOOLS" --no-skills --no-rules "$@"
}

cmd_stop() {
    require_podman
    podman stop "$OLLAMA_CONTAINER" 2>/dev/null && log "Ollama stopped." || warn "Ollama was not running."
}

cmd_logs() {
    require_podman
    podman logs -f "$OLLAMA_CONTAINER"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
CMD="${1:-}"
shift || true

case "$CMD" in
    setup)       cmd_setup ;;
    pull-model)  cmd_pull_model ;;
    start)       cmd_start "$@" ;;
    stop)        cmd_stop ;;
    logs)        cmd_logs ;;
    *)
        echo "Usage: $0 {setup|pull-model|start [omp-args]|stop|logs}"
        exit 1
        ;;
esac
