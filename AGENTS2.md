# Agent Context: Local-AI Repository

## Core Operational Constraints (CRITICAL)
- **Hardware Versatility**: Supports CPU, AMD iGPU (via Vulkan), and discrete GPUs.
- **Acceleration**: When using AMD iGPU, ensure `/dev/dri` is mounted and `OLLAMA_VULKAN=1` is configured.
- **Memory Management**: Critical to monitor RAM/VRAM. `num_ctx` sizing is highly dependent on available memory (e.g., 64K context requires significant headroom).
- **Authentication**: In `models.yml`, `auth: none` is required for certain Ollama configurations.
/
- **Inference Latency**: Expect variable latency. CPU prefill is significantly slower than GPU/iGPU.

## Repository Knowledge Map
- **Documentation**:
    - Stack/Inference details: `software-stack.md`, `prefill.md`
    - Deployment guide: `deployments/README.md`
    - Prompting/Anatomy: `README.md`
- **Configuration Locations**:
    - Ollama Modelfiles: `deployments/ollama/modelfiles/`
    - Agent (omp) Configs: `deployments/omp/config/` (`models.yml`, `config.yml`)
    - Deployment Orchestration: `deployments/compose.yaml` (Docker), `deployments/podman/kube/ollama.yaml` (Podman/K8s)
- **External Data**: `import/` contains external docs for context.

## Actionable Command Catalog
*Run these from the `deployments/` directory.*

| Goal | Command |
|------|---------|
| One-time Environment Setup | `bash scripts/setup.sh` |
| Start/Stop Inference (Ollama) | `docker compose up -d ollama` or `podman kube play ...` |
| Update/Pull Model Weights | `bash ollama/scripts/pull-model.sh` |
| Launch Agentic Harness (omp) | `bash omp/scripts/start-omp.sh` |
| Inspect Running Services | `docker compose ps` or `podman ps` |

## Task-Specific Instructions
- **When asked to modify deployment**: Always check `compose.yaml` or `ollama.yaml` for compatibility with the existing hardware (CPU/iGPU/GPU) and ensure appropriate volume/device mounts (like `/dev/dri` for iGPU).
- **When asked to expand context**: Check `prefill.md` for the impact of increasing `num_ctx`.
- **When troubleshooting Ollama**: Verify `ollama/modelfiles/gemma4.Modelfile` matches the requested model and check `OLLAMA_VULKAN` or `CUDA_VISIBLE_DEVICES` settings.
