# Local AI Deployments

Docker/Podman setup scripts for running large language models locally.

## Available Deployments

| Deployment | Hardware | Model | Harness | RAM |
|---|---|---|---|---|
| [local-cpu](./local-cpu/) | CPU-only | Gemma 4 26B Q4_K_M | oh-my-pi | ≥32 GB |

## Choosing a Deployment

**CPU-only machine (≥32 GB RAM)** → [`local-cpu/`](./local-cpu/)

**NVIDIA/AMD GPU** → Not yet documented here. See [`../software-stack.md`](../software-stack.md) for inference engine options (Ollama with GPU, vLLM, TabbyAPI).