# Local LLM Hosting: Tools, Stack Positions, and Recommendations

> Goal: GPU server for inference → authenticated web UI + OpenAI-compatible API for tools like opencode.

---

## The Stack in One Picture

```
┌─────────────────────────────────────────────────────────────┐
│  External Tools (opencode, Continue, LangChain, curl, ...)  │
└────────────────────────┬────────────────────────────────────┘
                         │ OpenAI-compatible HTTP API
┌────────────────────────▼────────────────────────────────────┐
│  Web UI / API Gateway Layer                                 │
│  (Open WebUI, LocalAI, text-generation-webui)               │
│  → authentication, user management, model switching         │
└────────────────────────┬────────────────────────────────────┘
                         │ internal API call
┌────────────────────────▼────────────────────────────────────┐
│  Inference Engine Layer                                     │
│  (llama.cpp, Ollama, vLLM, TabbyAPI, Aphrodite)             │
│  → loads model, runs GPU/CPU math, streams tokens           │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│  Hardware                                                   │
│  (NVIDIA/AMD GPU, Apple Silicon, CPU)                       │
└─────────────────────────────────────────────────────────────┘
```

Each layer can be mixed and matched. Most inference engines expose an OpenAI-compatible API, so the UI/gateway layer is interchangeable.

---

## Inference Engines

These do the actual computation: load a model file, accept a prompt, produce tokens.

### [llama.cpp](https://github.com/ggerganov/llama.cpp)

**Layer:** Raw inference engine (C/C++)

The original high-performance LLM runtime for consumer hardware. Loads models in **GGUF** format — a single quantized file that can be memory-mapped from disk. Ships with `llama-server`, a built-in HTTP server.

- **APIs:** OpenAI-compatible (`/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`), plus `/tokenize`, `/health`
- **GPU support:** NVIDIA (CUDA), AMD (ROCm), Apple Silicon (Metal), Vulkan, CPU fallback
- **Authentication:** None built-in
- **Concurrency:** Poor — single-request queue; each additional concurrent user increases time-to-first-token exponentially
- **Quantization formats:** GGUF (2–8 bit, mixed precision)

**Best for:** Single user, edge devices, CPU-only servers, maximum portability, minimum dependencies.  
**Not for:** Multiple concurrent users.

---

### [Ollama](https://ollama.com)

**Layer:** Model manager + API wrapper around llama.cpp

Ollama is a convenience layer on top of llama.cpp. It handles model downloading (from `ollama.com` registry), lifecycle management (automatic load/unload), and exposes a clean REST API. The inference core is llama.cpp — Ollama adds ~13–80% latency overhead from its abstraction.

- **APIs:** OpenAI-compatible + native Ollama API (`/api/chat`, `/api/generate`, `/api/pull`)
- **GPU support:** Same as llama.cpp (inherits backend)
- **Authentication:** Single API key via `OLLAMA_API_KEY` env var — no roles, no per-user isolation
- **Concurrency:** Same fundamental limitation as llama.cpp; slightly better with `OLLAMA_NUM_PARALLEL`

**Best for:** Getting started quickly, desktop use, development, pulling models without manual GGUF downloads.  
**Not for:** Production multi-user serving; performance-critical workloads.

> On CPU-only deployments, the [prefill phase](prefill.md) dominates time-to-first-token. Ollama's abstraction overhead compounds this — expect 2–6 minutes before the first output token on large models with a full tool schema loaded.

---

### [vLLM](https://github.com/vllm-project/vllm)

**Layer:** High-throughput inference server (Python)

Production-grade inference engine designed from scratch for multi-user serving. The key innovation is **PagedAttention**: the KV cache (the "memory" of the conversation context) is divided into fixed-size non-contiguous pages instead of reserved contiguous blocks. This eliminates 60–80% of memory fragmentation, allowing far more concurrent requests per GPU.

Combined with **continuous batching** (incoming requests are slotted into the next available batch position rather than waiting for a full batch to complete), vLLM achieves ~35× higher throughput than llama.cpp at 16 concurrent users.

- **APIs:** OpenAI-compatible (`/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`)
- **GPU support:** NVIDIA (primary, best optimized), AMD (experimental), Intel, Google TPU, AWS Inferentia; multi-GPU tensor/pipeline parallelism
- **Authentication:** Single API key via `--api-key`; no role system — pair with Open WebUI or a reverse proxy for multi-user auth
- **Quantization formats:** GGUF, AWQ, GPTQ, INT4/INT8, FP8
- **Model source:** HuggingFace Hub (or local path); does **not** use GGUF by default but GGUF support exists

**Best for:** Multi-user GPU server, production inference, maximum throughput.  
**Not for:** CPU-only machines; simple single-user desktop use.

---

### [TabbyAPI](https://github.com/theroyallab/tabbyAPI)

**Layer:** FastAPI inference server, ExllamaV3-optimized

A lightweight OpenAI-compatible API server built specifically around **ExllamaV3** — a highly optimized NVIDIA inference library using **EXL2** quantization. EXL2 is VRAM-efficient and faster than GGUF on NVIDIA cards when the model fits in VRAM.

Supports PagedAttention on Ampere+ GPUs and continuous dynamic batching. More constrained than vLLM (NVIDIA only, ExllamaV3 backend only) but lower overhead and excellent VRAM efficiency.

- **APIs:** OpenAI-compatible
- **GPU support:** NVIDIA Ampere+ (optimized); no AMD/CPU
- **Authentication:** None built-in
- **Quantization formats:** EXL2, GPTQ

**Best for:** NVIDIA GPU + EXL2-quantized models, efficient single-server setup.  
**Not for:** AMD/CPU, or when you need the broadest model compatibility.

---

### [Aphrodite Engine](https://github.com/PygmalionAI/aphrodite-engine)

**Layer:** High-throughput inference server (vLLM-derived)

Maintained by PygmalionAI, Aphrodite is a fork/extension of vLLM focused on broader quantization support and slightly broader GPU compatibility (supports Pascal-era GPUs, GTX 10xx). Architecture is identical to vLLM: PagedAttention + continuous batching.

- **APIs:** OpenAI-compatible
- **GPU support:** NVIDIA (Pascal+), AMD, Intel, Google TPU, AWS Inferentia
- **Authentication:** Typically via reverse proxy
- **Quantization formats:** AQLM, AWQ, GPTQ, GGUF, Marlin, and more — widest format support of any engine

**Best for:** vLLM use cases where you need broader quantization format support or older NVIDIA GPUs.  
**Not for:** Simple setups; same complexity as vLLM.

---

## Web UI / API Gateway Layer

These sit in front of inference engines and add user management, authentication, and a browser interface.

### [Open WebUI](https://github.com/open-webui/open-webui)

**Layer:** Web UI + API gateway

The de-facto standard web frontend for local LLMs. A self-hosted chat interface that proxies to any OpenAI-compatible backend. It is backend-agnostic — you can point it at Ollama, vLLM, llama.cpp, LM Studio, or any other engine without changing client code.

- **Backends:** Any OpenAI-compatible API; native Ollama support
- **Authentication:**
  - JWT (HS256, signed with `WEBUI_SECRET_KEY`)
  - Per-user API keys (`sk-...` prefixed Bearer tokens)
  - OAuth/OIDC (works with Authelia, Authentik, Keycloak)
  - Role-based: admin / user
- **API access:** External tools use `http://openwebui-host/api/v1/` with Bearer auth — same OpenAI schema
- **Features:** Multi-user chat history, RAG (document upload + vector search), model management, image generation, tool plugins

**Best for:** The UI + auth layer in a multi-user server setup. Tools like opencode connect to Open WebUI's API endpoint instead of directly to the inference engine — Open WebUI handles auth and forwards the request.  
**Not for:** Replacing the inference engine; it adds latency as a proxy.

---

### [LocalAI](https://github.com/mudler/LocalAI)

**Layer:** Unified API gateway + multi-backend orchestrator

LocalAI is a self-hosted drop-in replacement for the OpenAI API. Unlike Open WebUI (which is primarily a UI), LocalAI manages multiple inference backends itself (llama.cpp, vLLM, Whisper, Stable Diffusion, etc.) and exposes a single unified OpenAI-compatible endpoint.

- **Backends:** 36+ including llama.cpp, vLLM, HuggingFace Transformers, Whisper (audio), diffusion models (images)
- **Authentication:** Full multi-user system — role-based (admin/user), OAuth (GitHub, OIDC), per-user API keys, usage tracking. Enabled via `LOCALAI_AUTH=true`
- **API:** OpenAI-compatible, including tool/function calling
- **Web UI:** Built-in React UI (model management, basic chat)

**Best for:** When you need a single API endpoint for multiple modalities (text + audio + images) with built-in multi-user auth, without running Open WebUI separately.  
**Not for:** Best-in-class chat UI (Open WebUI is better for that).

---

### [text-generation-webui](https://github.com/oobabooga/text-generation-webui) (oobabooga)

**Layer:** Web UI + multi-backend wrapper

The original "everything in one" local LLM tool. Runs inference internally via pluggable backends (llama.cpp, ExllamaV3, HuggingFace Transformers, TensorRT-LLM) and exposes a web interface.

- **Backends:** llama.cpp, ExllamaV3, Transformers, TensorRT-LLM (hot-swappable)
- **Authentication:** API key + admin key via flags; web UI has a multi-user mode for separate chat histories — but **API does not support concurrent multi-user requests** (blocking issue, unfixed)
- **API:** OpenAI-compatible + Anthropic-compatible
- **Features:** Character/persona system, LoRA fine-tuning, notebook mode, tool/function calling, vision

**Best for:** Experimentation, character chats, fine-tuning workflows, single-user power users.  
**Not for:** Production API serving with multiple concurrent clients.

---

### [LM Studio](https://lmstudio.ai)

**Layer:** Desktop app + headless inference server

A polished desktop application for discovering, downloading, and running models. Ships with a headless server daemon (`llmstudio serve`) suitable for GPU rigs without a monitor.

- **Authentication:** None built-in
- **APIs:** OpenAI-compatible, Anthropic-compatible
- **GPU support:** NVIDIA, AMD, Apple Silicon, Intel
- **Concurrency:** Supports parallel requests with continuous batching

**Best for:** Developer workstations, easy model discovery, transitioning from desktop to headless server.  
**Not for:** Production multi-user deployments without an auth proxy.

---

## Quantization Formats: Quick Reference

| Format | Where it runs | Speed | Quality | Notes |
|--------|--------------|-------|---------|-------|
| **GGUF** | Everywhere (CPU, all GPUs) | Good | Good | Most portable; llama.cpp native |
| **EXL2** | NVIDIA only | Faster | Good | Mixed precision, best NVIDIA VRAM efficiency |
| **GPTQ** | NVIDIA/AMD | Moderate | Good | Older standard, widely supported |
| **AWQ** | NVIDIA/AMD | Good | Better | Activation-aware, better quality than GPTQ |
| **FP8/INT8** | NVIDIA Ampere+ | Fast | Better | vLLM native, near-native quality |

---

## Recommended Stack for Your Use Case

**Goal:** GPU server → authenticated web UI + OpenAI-compatible API for opencode and other tools.

```
┌─────────────────────────────────────────────────────────────────┐
│  opencode / other tools                                         │
│  → OPENAI_BASE_URL=https://your-server/api/v1                   │
│  → OPENAI_API_KEY=sk-your-user-key                              │
└────────────────────────┬────────────────────────────────────────┘
                         │ HTTPS + Bearer token
┌────────────────────────▼────────────────────────────────────────┐
│  Open WebUI  (port 3000, or behind nginx)                       │
│  → JWT + per-user API keys + OAuth                              │
│  → web chat interface for humans                                │
│  → proxies API requests to vLLM                                 │
└────────────────────────┬────────────────────────────────────────┘
                         │ internal HTTP (no auth needed)
┌────────────────────────▼────────────────────────────────────────┐
│  vLLM  (port 8000, localhost only)                              │
│  → loads model from HuggingFace / local path                    │
│  → PagedAttention + continuous batching                         │
│  → handles N concurrent users efficiently                       │
└─────────────────────────────────────────────────────────────────┘
```

**Why vLLM over Ollama/llama.cpp here:**  
The moment more than one person (or tool) sends a request concurrently, llama.cpp/Ollama latency spikes badly. vLLM's PagedAttention architecture handles concurrent requests with near-linear scaling. At 16 concurrent requests, vLLM achieves ~35× higher throughput.

**Why Open WebUI over LocalAI here:**  
Open WebUI has a better chat UI, is more actively developed, and its auth model (JWT + per-user `sk-` API keys) integrates cleanly with tools that expect an OpenAI-style API key. LocalAI is a good alternative if you need a single service managing multiple modalities (audio, images) with built-in auth and no separate UI needed.

### Quick-start commands

```bash
# 1. Start vLLM (GPU server, model stays on localhost)
pip install vllm
vllm serve mistralai/Mistral-7B-Instruct-v0.3 \
  --dtype auto \
  --port 8000 \
  --host 127.0.0.1  # only accessible locally; Open WebUI talks to it directly

# 2. Start Open WebUI (Docker)
docker run -d \
  -p 3000:8080 \
  -e OPENAI_API_BASE_URL=http://host.docker.internal:8000/v1 \
  -e OPENAI_API_KEY=unused \
  -v open-webui:/app/backend/data \
  --name open-webui \
  ghcr.io/open-webui/open-webui:main

# 3. Configure opencode (or any OpenAI-compatible tool)
# In opencode config or env:
# OPENAI_BASE_URL=http://your-server:3000/api/v1
# OPENAI_API_KEY=sk-<key from Open WebUI user settings>
```

For HTTPS + external access, put Nginx or Caddy in front of Open WebUI on port 443.

---

## Decision Matrix

| Need | Pick |
|------|------|
| Single user, fast, minimal setup | **Ollama** + Open WebUI |
| Multi-user GPU server (your case) | **vLLM** + Open WebUI |
| Multi-user + images/audio from one endpoint | **LocalAI** (with vLLM backend) |
| NVIDIA + EXL2 models, lightweight | **TabbyAPI** + Open WebUI |
| Desktop experimentation | **LM Studio** |
| Max portability / CPU only | **llama.cpp** directly |
| Character chats / fine-tuning workflows | **text-generation-webui** |

---

## Tool Interoperability

All inference engines expose an OpenAI-compatible API. This means:

- **[Open WebUI](https://github.com/open-webui/open-webui)** can connect to any of them — switch inference engines without changing your UI or client config
- **[opencode](https://github.com/sst/opencode)**, [Continue](https://continue.dev), [LangChain](https://github.com/langchain-ai/langchain), [LiteLLM](https://github.com/BerriAI/litellm), and any other tool expecting an OpenAI API just work
- You can run **multiple inference engines** simultaneously and have Open WebUI expose them as different "models" to users
- **[LocalAI](https://github.com/mudler/LocalAI)** can sit in front of vLLM to add auth + multimodal, while still forwarding LLM requests to vLLM

The OpenAI API compatibility layer is the glue that makes the whole ecosystem composable.
