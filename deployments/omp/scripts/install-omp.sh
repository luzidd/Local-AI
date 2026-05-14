#!/usr/bin/env bash
# install-omp.sh -- Install oh-my-pi (omp) natively on the host, without a container.
#
# Uses the official omp installer script, which automatically selects Bun when
# available (requires Bun >= 1.3.7), otherwise installs a prebuilt binary.
#
# After install, copies the project's config.yml, a localhost-patched
# models.yml, and a safety hook to ~/.omp/agent/ so omp talks to Ollama
# on localhost:11434 and asks for confirmation before destructive commands.
#
# Usage:
#   bash scripts/install-omp.sh [--binary | --source]
#
#   --binary   Force prebuilt binary install (no Bun required)
#   --source   Force Bun source install (requires Bun >= 1.3.7)
#   (default)  Let the installer auto-select (Bun if available)
#
# After install:
#   omp                 -- start the agent
#   omp update          -- update to the latest version
#   omp --list-models   -- verify Ollama models are visible
#
# Requires Ollama to be running on localhost:11434.
# Start it with:  bash podman/bind-mount/podman.sh start  (or podman/quadlets/install.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
OMP_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"
INSTALLER_URL="https://raw.githubusercontent.com/can1357/oh-my-pi/main/scripts/install.sh"

log()  { printf '\033[1;32m[omp]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[omp]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[omp]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl not found"

# -- Parse flags ---------------------------------------------------------------
INSTALL_FLAGS=""
case "${1:-}" in
    --binary) INSTALL_FLAGS="--binary" ;;
    --source) INSTALL_FLAGS="--source" ;;
    "")       ;;
    *) die "Unknown flag '$1'. Use --binary or --source." ;;
esac

# -- Install omp ---------------------------------------------------------------
log "Running omp installer..."
if [[ -n "$INSTALL_FLAGS" ]]; then
    curl -fsSL "$INSTALLER_URL" | sh -s -- $INSTALL_FLAGS
else
    curl -fsSL "$INSTALLER_URL" | sh
fi

# Reload PATH in case the installer added a new directory
if [[ -f "$HOME/.bashrc" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.bashrc" 2>/dev/null || true
fi
export PATH="$HOME/.local/bin:$HOME/.omp/bin:$PATH"

command -v omp >/dev/null 2>&1 || die "omp not found on PATH after install. Check the installer output above."
log "omp installed: $(omp --version 2>&1 | head -1)"

# -- Write config files --------------------------------------------------------
log "Writing config to $OMP_AGENT_DIR ..."
mkdir -p "$OMP_AGENT_DIR"

# config.yml is the same as the container version
cp "$DEPLOY_DIR/config/config.yml" "$OMP_AGENT_DIR/config.yml"

# models.yml needs baseUrl pointing to localhost, not the Docker service name
sed 's|http://ollama:11434|http://localhost:11434|g' \
    "$DEPLOY_DIR/config/models.yml" > "$OMP_AGENT_DIR/models.yml"

# Extension: inverted permission model — prompts before any non-read-only tool
EXT_SRC="$DEPLOY_DIR/config/extensions/confirm-destructive.ts"
EXT_DEST="$OMP_AGENT_DIR/extensions/confirm-destructive.ts"
mkdir -p "$(dirname "$EXT_DEST")"
cp "$EXT_SRC" "$EXT_DEST"

log "Config files and extension written."

# -- Done ----------------------------------------------------------------------
log ""
log "Done. Run 'omp' from your workspace directory to start."
log "Ollama must be running on localhost:11434 before starting omp."
