#!/usr/bin/env bash
# install-llama-server.sh -- Install llama.cpp server as a systemd user service via Podman Quadlets.
#
# Deploys: Gemma 4 26B Q6 MoE with Vulkan GPU acceleration + expert offloading
# Port:    http://127.0.0.1:11435 (coexists with Ollama on 11434)
# Storage: Persistent volume for model cache (~50GB)
#
# Usage:
#   bash podman/quadlets/install-llama-server.sh
#
# After install, manage with systemd:
#   systemctl --user status podman-llama-server
#   systemctl --user stop podman-llama-server
#   systemctl --user restart podman-llama-server
#   journalctl --user -u podman-llama-server -f
#
# Test the server:
#   curl http://127.0.0.1:11435/health
#   curl http://127.0.0.1:11435/v1/models
#
# See deployments/podman/kube/TUNING-GUIDE.md for performance tuning.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBE_DIR="$(dirname "$SCRIPT_DIR")/kube"
SYSTEMD_DIR="$HOME/.config/containers/systemd"

log()  { printf '\033[1;32m[llama-server]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[llama-server]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[llama-server]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

command -v podman    >/dev/null 2>&1 || die "podman not found"
command -v systemctl >/dev/null 2>&1 || die "systemctl not found"

# -- GPU check -----------------------------------------------------------------
log "Checking GPU availability..."
if [ ! -d "/dev/dri" ]; then
    die "No /dev/dri found. GPU required for this deployment."
fi

if [ ! -c "/dev/dri/renderD128" ] && [ ! -c "/dev/dri/card0" ]; then
    warn "No GPU render device found. Container may fail to access GPU."
fi

log "Found DRI devices:"
ls -la /dev/dri/ | grep -E "card|render"

# -- System requirements check -------------------------------------------------
log "Checking system requirements..."

total_ram_gb=$(free -g | awk '/^Mem:/ {print $2}')
if [ "$total_ram_gb" -lt 24 ]; then
    warn "Less than 24GB RAM detected (found: ${total_ram_gb}GB)"
    warn "Model may fail to load. 32GB+ recommended for Q6 with expert offloading."
fi

# -- Install quadlet files -----------------------------------------------------
mkdir -p "$SYSTEMD_DIR"

log "Installing llama-server quadlet to $SYSTEMD_DIR ..."
cp "$SCRIPT_DIR/podman-llama-server.kube" "$SYSTEMD_DIR/"
cp "$KUBE_DIR/llama-server.yaml"           "$SYSTEMD_DIR/"

# -- Pull image ----------------------------------------------------------------
log "Pulling llama.cpp server image (Vulkan variant)..."
podman pull ghcr.io/ggml-org/llama.cpp:server-vulkan

# -- Reload systemd ------------------------------------------------------------
log "Reloading systemd user daemon..."
systemctl --user daemon-reload

if ! systemctl --user cat podman-llama-server.service >/dev/null 2>&1; then
    die "podman-llama-server.service was not generated. Check: journalctl --user -xe"
fi

# -- Start service -------------------------------------------------------------
log "Starting podman-llama-server.service..."
log ""
log "Note: First start automatically downloads the model from Hugging Face."
log "  Model: gemma-4-26B-A4B-it-UD-Q6_K.gguf (~22GB)"
log "  Time:  5-15 minutes (depending on internet speed)"
log ""
log "For manual download or to switch quantization variants, see:"
log "  deployments/podman/kube/MODEL-DOWNLOAD.md"
log ""

systemctl --user start --no-block podman-llama-server.service

# -- Wait for startup ----------------------------------------------------------
log "Waiting for server to be ready (checking health endpoint)..."
log "You can monitor progress with: journalctl --user -u podman-llama-server -f"
log ""

attempts=0
until curl -sf http://localhost:11435/health >/dev/null 2>&1; do
    printf '.'
    sleep 5
    attempts=$((attempts + 1))
    if [[ $attempts -gt 180 ]]; then
        echo ""
        warn "Server did not become ready after 15 minutes."
        warn "This is normal if the model is still downloading."
        warn "Check logs: journalctl --user -u podman-llama-server -f"
        break
    fi
done

if curl -sf http://localhost:11435/health >/dev/null 2>&1; then
    echo ""
    log "Server is ready!"
    echo ""
    
    # Show available models
    log "Available models:"
    curl -s http://localhost:11435/v1/models | jq -r '.data[].id // .models[]? // "No models found"' 2>/dev/null || echo "  (Run 'curl http://localhost:11435/v1/models' to check)"
fi

# -- Summary -------------------------------------------------------------------
echo ""
log "Installation complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Service: podman-llama-server.service"
echo "  API URL: http://127.0.0.1:11435"
echo ""
echo "  Useful commands:"
echo "    systemctl --user status podman-llama-server"
echo "    systemctl --user restart podman-llama-server"
echo "    journalctl --user -u podman-llama-server -f"
echo ""
echo "  Health check:"
echo "    curl http://127.0.0.1:11435/health"
echo ""
echo "  List models:"
echo "    curl http://127.0.0.1:11435/v1/models"
echo ""
echo "  Test inference:"
echo "    bash scripts/test-llama.sh"
echo ""
echo "  Model downloads:"
echo "    See: deployments/podman/kube/MODEL-DOWNLOAD.md"
echo ""
echo "  Performance tuning:"
echo "    See: deployments/podman/kube/TUNING-GUIDE.md"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log "The service will start automatically on next login."
