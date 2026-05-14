#!/usr/bin/env bash
# pull-model.sh — Select and pull a model from the Ollama registry.
#                 All listed models fit within 20-24 GB of RAM.
#
# Usage:
#   bash scripts/pull-model.sh [--container <name>]
#
#   --container <name>   Use 'podman exec <name>' instead of 'docker compose exec'.
#                        Required when Ollama is running via quadlets/systemd.
#                        Container name is 'ollama-ollama' (kube) or 'ollama' (container).
#
# Re-runnable: safe to call again to pull additional models.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

log()  { printf '\033[1;32m[model]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[model]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

# ── Parse args ────────────────────────────────────────────────────────────────
EXEC_CONTAINER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --container) EXEC_CONTAINER="${2:?'--container requires a value'}"; shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── Exec helpers ──────────────────────────────────────────────────────────────
ollama_exec() {
    if [[ -n "$EXEC_CONTAINER" ]]; then
        podman exec "$EXEC_CONTAINER" ollama "$@"
    else
        docker compose exec ollama ollama "$@"
    fi
}

ollama_cp() {
    # Copy a local file into the Ollama container.
    local src="$1" dest_path="$2"
    if [[ -n "$EXEC_CONTAINER" ]]; then
        podman cp "$src" "$EXEC_CONTAINER:$dest_path"
    else
        docker compose cp "$src" "ollama:$dest_path"
    fi
}

check_running() {
    if [[ -n "$EXEC_CONTAINER" ]]; then
        podman container inspect "$EXEC_CONTAINER" --format '{{.State.Status}}' 2>/dev/null \
            | grep -q "running" || die "Container '$EXEC_CONTAINER' is not running."
    else
        docker compose ps ollama | grep -q "running" \
            || die "Ollama container is not running. Run 'docker compose up -d ollama' first."
    fi
}

# ── Model catalogue ───────────────────────────────────────────────────────────
# Fields: "ollama_tag|display_name|ram_estimate|modelfile|local_alias"
#
# All entries fit within ~20 GB weights + KV cache on a 32 GB host.
# To add a model: append a line following the same format.
#   modelfile: filename inside modelfiles/ (empty = no registration step)
#   local_alias: name for 'ollama create' (empty = no registration step)
MODELS=(
    "gemma4:e2b-it-q4_K_M|Gemma 4 E2B edge Q4_K_M (2.3B effective)|~7 GB weights||"
    "gemma4:e2b-it-q8_0|Gemma 4 E2B edge Q8_0 (2.3B effective)|~8 GB weights||"
    "gemma4:e4b-it-q4_K_M|Gemma 4 E4B edge Q4_K_M (4.5B effective)|~10 GB weights||"
    "gemma4:e4b-it-q8_0|Gemma 4 E4B edge Q8_0 (4.5B effective)|~12 GB weights||"
    "gemma4:26b|Gemma 4 26B MoE (Q4_K_M)|~18 GB weights + ~7 GB KV @ 65K ctx|gemma4.Modelfile|gemma4-local"
    "gemma3:27b|Gemma 3 27B dense (Q4_K_M)|~16 GB weights||"
    "gemma3:12b|Gemma 3 12B dense (Q4_K_M)|~7 GB weights||"
    "gemma3:4b|Gemma 3 4B dense (Q4_K_M)|~3 GB weights||"
    "qwen3:14b|Qwen 3 14B (Q4_K_M)|~9 GB weights|qwen3-14b.Modelfile|qwen3-local"
    "kimi-vl:a3b-q4_K_M|Kimi VL 3B (Q4_K_M)|~2 GB weights||"
)

# ── Model selection menu ──────────────────────────────────────────────────────
echo ""
echo "Available models (all fit within 20-24 GB RAM):"
echo ""
printf '  %-4s %-42s %s\n' "Num" "Model" "RAM estimate"
printf '  %-4s %-42s %s\n' "---" "-----" "------------"
for i in "${!MODELS[@]}"; do
    IFS='|' read -r tag name ram _modelfile _alias <<< "${MODELS[$i]}"
    printf '  %-4s %-42s %s\n' "$((i+1))" "$name  [$tag]" "$ram"
done
echo ""
read -r -p "Choice [1-${#MODELS[@]}]: " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#MODELS[@]} )); then
    die "Invalid choice: '$choice'"
fi

IFS='|' read -r TAG NAME RAM MODELFILE_NAME LOCAL_ALIAS <<< "${MODELS[$((choice-1))]}"

# ── Pull ──────────────────────────────────────────────────────────────────────
check_running

log "Pulling $NAME ($TAG, $RAM)..."
log "This is a one-time download. Subsequent starts use the local cache."
ollama_exec pull "$TAG"

# ── Register tuned variant (if a Modelfile exists for this model) ─────────────
if [[ -n "$MODELFILE_NAME" && -n "$LOCAL_ALIAS" ]]; then
    MODELFILE="$DEPLOY_DIR/modelfiles/$MODELFILE_NAME"
    [[ -f "$MODELFILE" ]] || die "Modelfile not found at $MODELFILE"
    log "Registering $LOCAL_ALIAS from $MODELFILE_NAME..."
    ollama_cp "$MODELFILE" /tmp/Modelfile
    ollama_exec create "$LOCAL_ALIAS" -f /tmp/Modelfile
    log "Registered alias: $LOCAL_ALIAS"
fi

log "Done. Verify with:"
if [[ -n "$EXEC_CONTAINER" ]]; then
    log "  podman exec $EXEC_CONTAINER ollama list"
else
    log "  docker compose exec ollama ollama list"
fi
