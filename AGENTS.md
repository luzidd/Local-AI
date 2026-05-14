# Local-AI

Documentation and deployment repository for running LLMs locally on CPU hardware.

## Project Structure

- **Concept docs**: [`README.md`](README.md), [`prefill.md`](prefill.md), [`software-stack.md`](software-stack.md)
- **Deployment**: [`deployments/`](deployments/) — Ollama + oh-my-pi via Docker Compose (CPU-only, Gemma 4 26B Q4)
- **Import**: [`import/`](import/) — external documents for incoorporation into the project

## Deployment

Runs **Gemma 4 26B MoE** (Q4_K_M, ~18 GB RAM) via Ollama on a CPU-only machine.
The agentic harness is **oh-my-pi** (`omp`), running in a separate Bun-based container.

### Commands (run from `deployments/`)

| Task | Command |
|------|---------|
| One-time setup | `bash scripts/setup.sh` |
| Start Ollama | `docker compose up -d ollama` |
| Pull / re-register model | `bash ollama/scripts/pull-model.sh` |
| Start omp (interactive) | `bash omp/scripts/start-omp.sh` |

### Key Config Files

- [`ollama/modelfiles/gemma4.Modelfile`](deployments/ollama/modelfiles/gemma4.Modelfile) — sampling params, `num_ctx`, stop sequences
- [`omp/config/models.yml`](deployments/omp/config/models.yml) — Ollama provider + model definition for omp
- [`omp/config/config.yml`](deployments/omp/config/config.yml) — omp agent roles, compaction, retry settings

## Critical Constraints & Pitfalls

- **`num_ctx: 65536`** is the calibrated sweet spot. KV cache: 32K ≈ 3–4 GB, 65K ≈ 6–7 GB, 128K ≈ 12–16 GB. Host has ~10–14 GB free after weights load.
- **Never add GPU device config** to `compose.yaml` — CPU-only mode; adding GPU resources breaks the setup.
- **Q8 variant OOMs on 32 GB**: Q8 weights alone require ~32 GB. Only viable on ≥48 GB hosts.
- **`auth: none`** in `models.yml` is required — an empty `OLLAMA_API_KEY` env var is not equivalent; omp will silently filter out the provider without it.
- **`reasoning: false`** in `models.yml` is intentional — Gemma 4 thinking is prompt-controlled (prepend `<|think|>` to system prompt), not via API extension flags that Ollama doesn't support.
- **CPU prefill latency**: Expect 2–6 minutes before the first output token on large inputs. See [`prefill.md`](prefill.md).

## Documentation Map

| Topic | File |
|-------|------|
| Stack layers, inference engine comparison | [`software-stack.md`](software-stack.md) |
| Prefill vs decode, KV cache sizing | [`prefill.md`](prefill.md) |
| Prompt anatomy, agentic harness concepts | [`README.md`](README.md) |
| Deployment overview | [`deployments/README.md`](deployments/README.md) |
