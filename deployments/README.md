# CPU Deployment

Runs **Gemma 4 26B MoE** (Q4_K_M, ~18 GB) via [Ollama](https://ollama.com) on a CPU-only machine. The agentic harness is **[oh-my-pi](https://www.npmjs.com/package/@oh-my-pi/pi-coding-agent)** (`omp`), running in a separate Bun container.

---

## Prerequisites

| Requirement | Minimum | Notes |
|---|---|---|
| RAM | 32 GB | ~18 GB model weights + 6–7 GB KV cache + OS |
| Disk | 20 GB free | ~18 GB model, ~1 GB images |
| CPU | x86-64 or ARM64 | Physical core count → set `OLLAMA_NUM_THREADS` |
| Docker / Podman | Docker Engine 24+ or Podman 4+ | Compose v2 required (`docker compose`, not `docker-compose`) |
| Internet | Required once | For model pull and image builds during setup |

---

## Choosing a Deployment Method

If you are unsure, use **Docker Compose** with `bash scripts/setup.sh`. It is the default path and the shortest route to a working local setup.

| Your Setup | Recommended Method | Command |
|------------|-------------------|---------|
| **Docker Desktop / Docker Engine** | Compose (default) | `bash scripts/setup.sh` |
| **Podman + systemd auto-start** | Quadlets | `bash podman/quadlets/install.sh` |
| **Podman + manual control** | Bind-mount script | `bash podman/bind-mount/podman.sh setup` |
| **Kubernetes / OpenShift** | Kube manifest | `kubectl apply -f podman/kube/ollama.yaml` |

All methods run the same model (Gemma 4 26B Q4) with the same configuration.

## Glossary

- **Ollama**: the local model server that loads the model and serves responses over an API
- **omp**: the agentic harness that talks to Ollama and provides the interactive coding/chat interface
- **Modelfile**: the Ollama-specific configuration file that sets model parameters like context window and stop tokens

---

## Quick Start

Run from the `deployments/` directory:

```sh
bash scripts/setup.sh           # one-time: build images, pull model (~18 GB)
bash omp/scripts/start-omp.sh  # launch the interactive agentic harness
```

Subsequent runs only need `start-omp.sh`. Ollama persists the model between restarts.

**Windows:** Use `scripts/setup.ps1` and `omp/scripts/start-omp.ps1` instead.

## What Success Looks Like

After setup finishes, you should be able to confirm the stack with these checks:

```sh
docker compose ps
docker compose exec ollama ollama list
bash omp/scripts/start-omp.sh
```

Expected outcome:

- `docker compose ps` shows the `ollama` service as running and healthy
- `ollama list` includes `gemma4-local`
- `omp/scripts/start-omp.sh` opens the harness and can send requests to Ollama
- the first response may still take several minutes on CPU, especially with a large context

---

## Directory Structure

```
deployments/
├── compose.yaml           # Ollama + omp service definitions
├── scripts/
│   └── setup.sh / .ps1    # One-time setup (Compose-based, default)
├── podman/                # Podman-specific deployment methods
│   ├── bind-mount/
│   │   └── podman.sh      # Manual Podman commands (advanced/debugging)
│   ├── quadlets/          # Systemd service (recommended for Podman)
│   │   ├── install.sh     # Install Ollama as systemd user service
│   │   ├── podman-ollama.kube
│   │   ├── podman-ollama.container
│   │   ├── podman-ollama-data.volume
│   │   └── podman-local-ai.network
│   └── kube/
│       └── ollama.yaml    # Kubernetes/OpenShift pod manifest
├── ollama/
│   ├── modelfiles/        # Modelfiles (sampling params, num_ctx, stop sequences)
│   │   ├── gemma4.Modelfile
│   │   └── qwen3-14b.Modelfile
│   └── scripts/
│       └── pull-model.sh  # Model management (works with all deployment methods)
├── omp/
│   ├── Dockerfile.omp     # Builds the oh-my-pi container image
│   ├── config/
│   │   ├── models.yml     # Ollama provider + model definition for omp
│   │   ├── config.yml     # omp agent roles, compaction, retry settings
│   │   └── extensions/    # omp safety/permission extensions
│   └── scripts/
│       ├── start-omp.sh / .ps1 # Launch the interactive omp session
│       └── install-omp.sh      # Install omp natively (no container)
└── workspace/             # Created by setup.sh — mounted into omp container
```

---

## Config Files

### `ollama/modelfiles/gemma4.Modelfile`

Controls how Ollama serves the model. Key parameters:

| Parameter | Value | Why |
|---|---|---|
| `FROM` | `gemma4:26b` | Q4_K_M variant (~18 GB) |
| `temperature` | 1.0 | Google's recommended baseline for Gemma 4 |
| `top_p` / `top_k` | 0.95 / 64 | Recommended sampling for Gemma 4 |
| `num_ctx` | 65536 | Calibrated sweet spot — see [KV cache notes](#kv-cache--num_ctx) |
| `num_thread` | 8 | Override with `OLLAMA_NUM_THREADS` env var |
| `stop` | `<end_of_turn>`, `<eos>` | Gemma 4 stop sequences |

### `omp/config/models.yml`

Tells oh-my-pi where to find the model:

- `baseUrl: http://ollama:11434/v1` — uses the Docker service name `ollama` (internal DNS). If running omp outside Docker, change to `http://localhost:11434/v1`.
- `auth: none` — **required**; an empty `OLLAMA_API_KEY` env var is not equivalent. Without this, omp silently filters out the provider.
- `reasoning: false` — Gemma 4 thinking is prompt-controlled (prepend `<|think|>` to the system prompt), not via API extension flags that Ollama doesn't support.

### `omp/config/config.yml`

Controls omp's behavior:

- All model roles (`default`, `smol`, `slow`, `plan`, `commit`) are mapped to `ollama/gemma4-local` — there is only one local model.
- **Compaction** is enabled: omp summarizes old turns when the context fills up. With `num_ctx: 65536` and `~16K` tokens of fixed tool overhead, this keeps sessions functional over long conversations.
- `retry.maxRetries: 3` with `baseDelayMs: 3000` — CPU inference is slow; retries help recover from timeouts.

---

## KV Cache & `num_ctx`

The KV cache is allocated upfront based on `num_ctx`, not actual usage. It lives in RAM alongside the model weights.

| `num_ctx` | KV cache size | Usable on 32 GB |
|---|---|---|
| 32 K | ~3–4 GB | Yes (leaves ~10 GB headroom) |
| **65 K** | **~6–7 GB** | **Yes — recommended** |
| 128 K | ~12–16 GB | Tight; may OOM depending on OS overhead |

At 65K, tool definitions (~16K tokens) consume ~25% of the window, leaving ~49K for conversation.

---

## Performance Expectations

| Phase | Typical rate |
|---|---|
| Prefill (processing input) | 50–150 tok/s |
| Decode (generating output) | 3–8 tok/s |

Expect up to **20 minutes** with a typical AMD Ryzen 5 PRO 4650U Laptop CPU before the first output token on a fresh request with a full context window loaded. This is normal — see [prefill.md](../../prefill.md) for a full explanation.

---

## Critical Constraints

- **Never add GPU device config** to `compose.yaml`. This is a CPU-only deployment; adding `devices` or `deploy.resources.reservations.devices` breaks it.
- **Q8 variant OOMs on 32 GB**: `gemma4:26b-q8_0` requires ~32 GB for weights alone, leaving no room for the KV cache. Only viable on ≥48 GB hosts.
- **Do not use `docker-compose` (v1).** The scripts require Compose v2 (`docker compose`).

## Troubleshooting by Symptom

### Ollama never becomes healthy

- verify Docker or Podman is installed and running
- run `docker compose logs ollama` to inspect startup failures
- confirm port `11434` is not already in use by another Ollama instance

### `ollama list` does not show `gemma4-local`

- rerun `bash ollama/scripts/pull-model.sh`
- confirm the base model pull completed successfully before the registration step
- check that `ollama/modelfiles/gemma4.Modelfile` still exists and matches the selected alias

### omp cannot see the model or provider

- verify `omp/config/models.yml` still points to `http://ollama:11434/v1` for the container-based setup
- keep `auth: none` in `omp/config/models.yml`; an empty API key is not equivalent
- confirm Ollama is healthy before starting `omp`

### The first reply is extremely slow

- this is expected on CPU, especially on the first request with a large context window
- see [prefill.md](../../prefill.md) for why the delay happens before the first token appears
- reduce context size only if you are deliberately changing the deployment tradeoff

---

## Alternative Deployment Methods

### Podman

Three Podman deployment options are available in the `podman/` directory:

**1. Systemd Quadlets (Recommended)**

Best for production use. Pick this if you want Ollama to start automatically on login.

```sh
bash podman/quadlets/install.sh    # choose kube or container method
systemctl --user status podman-ollama
bash podman/bind-mount/podman.sh start  # launch omp
```

**2. Bind-mount script**

For development and debugging. Pick this if you want direct manual control over the Podman containers.

```sh
bash podman/bind-mount/podman.sh setup  # one-time
bash podman/bind-mount/podman.sh start  # launch omp
```

**3. Kubernetes/OpenShift**

For cluster deployments. Ignore this unless you already know you want a Kubernetes-style deployment.

```sh
kubectl apply -f podman/kube/ollama.yaml
```

---

## Further Reading

| Topic | File |
|---|---|
| Why prefill is slow on CPU; KV cache sizing | [prefill.md](../../prefill.md) |
| Inference engines, web UIs, quantization | [software-stack.md](../../software-stack.md) |
| System prompts, tools, agentic harness concepts | [README.md](../../README.md) |
| All deployments | [deployments/README.md](../README.md) |
