# local-cpu Deployment

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

## Quick Start

Run from the `deployments/local-cpu/` directory:

```sh
bash scripts/setup.sh       # one-time: build images, pull model (~18 GB)
bash scripts/start-omp.sh   # launch the interactive agentic harness
```

Subsequent runs only need `start-omp.sh`. Ollama persists the model between restarts.

**Windows:** Use `scripts/setup.ps1` and `scripts/start-omp.ps1` instead.

---

## Directory Structure

```
local-cpu/
├── compose.yaml           # Ollama + omp service definitions
├── Dockerfile.omp         # Builds the oh-my-pi container image
├── config/
│   ├── Modelfile          # Sampling params, num_ctx, stop sequences
│   ├── models.yml         # Ollama provider + model definition for omp
│   └── config.yml         # omp agent roles, compaction, retry settings
├── scripts/
│   ├── setup.sh / .ps1    # One-time setup (build, pull, register model)
│   ├── pull-model.sh      # Re-pull or re-register the model with Ollama
│   ├── start-omp.sh / .ps1 # Launch the interactive omp session
│   └── podman.sh          # Podman-specific helpers
└── workspace/             # Created by setup.sh — mounted into omp container
```

---

## Config Files

### `config/Modelfile`

Controls how Ollama serves the model. Key parameters:

| Parameter | Value | Why |
|---|---|---|
| `FROM` | `gemma4:26b` | Q4_K_M variant (~18 GB) |
| `temperature` | 1.0 | Google's recommended baseline for Gemma 4 |
| `top_p` / `top_k` | 0.95 / 64 | Recommended sampling for Gemma 4 |
| `num_ctx` | 65536 | Calibrated sweet spot — see [KV cache notes](#kv-cache--num_ctx) |
| `num_thread` | 8 | Override with `OLLAMA_NUM_THREADS` env var |
| `stop` | `<end_of_turn>`, `<eos>` | Gemma 4 stop sequences |

### `config/models.yml`

Tells oh-my-pi where to find the model:

- `baseUrl: http://ollama:11434/v1` — uses the Docker service name `ollama` (internal DNS). If running omp outside Docker, change to `http://localhost:11434/v1`.
- `auth: none` — **required**; an empty `OLLAMA_API_KEY` env var is not equivalent. Without this, omp silently filters out the provider.
- `reasoning: false` — Gemma 4 thinking is prompt-controlled (prepend `<|think|>` to the system prompt), not via API extension flags that Ollama doesn't support.

### `config/config.yml`

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

Expect **2–6 minutes** before the first output token on a fresh request with a full context window loaded. This is normal — see [prefill.md](../../prefill.md) for a full explanation.

---

## Critical Constraints

- **Never add GPU device config** to `compose.yaml`. This is a CPU-only deployment; adding `devices` or `deploy.resources.reservations.devices` breaks it.
- **Q8 variant OOMs on 32 GB**: `gemma4:26b-q8_0` requires ~32 GB for weights alone, leaving no room for the KV cache. Only viable on ≥48 GB hosts.
- **Do not use `docker-compose` (v1).** The scripts require Compose v2 (`docker compose`).

---

## Podman

If using Podman instead of Docker, `scripts/podman.sh` contains the equivalent `podman` commands. Ensure your Podman installation has Compose support (`podman compose` or `podman-compose`).

---

## Further Reading

| Topic | File |
|---|---|
| Why prefill is slow on CPU; KV cache sizing | [prefill.md](../../prefill.md) |
| Inference engines, web UIs, quantization | [software-stack.md](../../software-stack.md) |
| System prompts, tools, agentic harness concepts | [README.md](../../README.md) |
| All deployments | [deployments/README.md](../README.md) |
