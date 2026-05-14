#!/usr/bin/env bash
# install-quadlets.sh -- Install Ollama as a systemd user service via Podman Quadlets.
#
# Two methods are supported:
#
#   kube      -- [Kube] quadlet wrapping kube/ollama.yaml  (requires Podman 4.4+, recommended)
#               Container name for exec: ollama-ollama  (pod-container)
#
#   container -- Classic [Container] + [Network] + [Volume] quadlets  (Podman 4.0+)
#               Container name for exec: ollama
#
# Usage:
#   bash podman/quadlets/install.sh [kube|container]
#
# All installed unit files are prefixed with podman- (e.g. podman-ollama.service).
#
# After install, manage Ollama like any systemd service:
#   systemctl --user status podman-ollama
#   systemctl --user stop podman-ollama
#   systemctl --user restart podman-ollama
#   journalctl --user -u podman-ollama -f
#
# Run omp once Ollama is running:
#   bash podman/bind-mount/podman.sh start
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
QUADLET_DIR="$SCRIPT_DIR"
KUBE_DIR="$(dirname "$SCRIPT_DIR")/kube"
SYSTEMD_DIR="$HOME/.config/containers/systemd"

log()  { printf '\033[1;32m[quadlet]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[quadlet]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[quadlet]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

command -v podman    >/dev/null 2>&1 || die "podman not found"
command -v systemctl >/dev/null 2>&1 || die "systemctl not found"

# -- Method selection ----------------------------------------------------------
METHOD="${1:-}"
if [[ -z "$METHOD" ]]; then
    echo ""
    echo "Select install method:"
    echo "  1) kube       -- [Kube] quadlet wrapping kube/ollama.yaml  (Podman 4.4+, recommended)"
    echo "  2) container  -- Classic [Container] + [Network] + [Volume] quadlets  (Podman 4.0+)"
    echo ""
    read -r -p "Choice [1/2]: " choice
    case "$choice" in
        1|kube)      METHOD=kube ;;
        2|container) METHOD=container ;;
        *) die "Invalid choice: '$choice'. Pass 'kube' or 'container'." ;;
    esac
fi

case "$METHOD" in
    kube|container) ;;
    *) die "Unknown method '$METHOD'. Use 'kube' or 'container'." ;;
esac

log "Using method: $METHOD"

# -- Install unit files --------------------------------------------------------
mkdir -p "$SYSTEMD_DIR"

if [[ "$METHOD" == "kube" ]]; then
    log "Installing kube quadlet files to $SYSTEMD_DIR ..."
    # The .kube unit references ollama.yaml by relative path -- both must be co-located
    cp "$QUADLET_DIR/podman-ollama.kube" "$SYSTEMD_DIR/"
    cp "$KUBE_DIR/ollama.yaml"           "$SYSTEMD_DIR/"
    EXEC_CONTAINER="ollama-ollama"  # podman kube play names: <pod>-<container>
else
    log "Installing container quadlet files to $SYSTEMD_DIR ..."
    cp "$QUADLET_DIR/podman-ollama.container"   "$SYSTEMD_DIR/"
    cp "$QUADLET_DIR/podman-ollama-data.volume" "$SYSTEMD_DIR/"
    cp "$QUADLET_DIR/podman-local-ai.network"   "$SYSTEMD_DIR/"
    EXEC_CONTAINER="ollama"
fi

# -- Pull image ----------------------------------------------------------------
log "Pulling Ollama image (this may take a while on first run)..."
podman pull docker.io/ollama/ollama:latest

# -- Reload and verify ---------------------------------------------------------
log "Reloading systemd user daemon..."
systemctl --user daemon-reload

if ! systemctl --user cat podman-ollama.service >/dev/null 2>&1; then
    die "podman-ollama.service was not generated. Check: journalctl --user -xe"
fi

# -- Enable and start ----------------------------------------------------------
# Note: generated units cannot be enabled via systemctl -- the quadlet generator
# honours [Install] WantedBy= automatically. No 'enable' step is needed or possible.

log "Starting podman-ollama.service..."
systemctl --user start --no-block podman-ollama.service

# -- Wait for healthy -----------------------------------------------------------
log "Waiting for Ollama API to be ready (this may take up to 30 s)..."
attempts=0
until curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; do
    printf '.'
    sleep 3
    attempts=$((attempts + 1))
    [[ $attempts -gt 20 ]] && echo "" && die "Ollama did not become ready. Check: journalctl --user -u podman-ollama -f"
done
echo ""
log "Ollama is ready."

# -- Model pull (optional) -----------------------------------------------------
read -r -p "Pull a model now? [y/N] " answer
if [[ "${answer,,}" == "y" ]]; then
    bash "$SCRIPT_DIR/pull-model.sh" --container "$EXEC_CONTAINER"
fi

log ""
log "Done. Ollama will now start automatically on login."
log "Run omp with: bash podman/bind-mount/podman.sh start"
