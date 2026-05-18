# Gemma 4 26B Q6 Tuning Guide (16GB VRAM)

## System Configuration

**Target Setup:**
- GPU: 16GB VRAM with Vulkan support
- Model: Gemma 4 26B MoE Q6_K (~22GB)
- Context: 128k tokens
- Strategy: GPU for core layers, CPU RAM for experts

## Key Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LLAMA_ARG_N_GPU_LAYERS` | `20` | Number of model layers on GPU. Start conservative, increase if VRAM headroom exists. |
| `LLAMA_ARG_N_CPU_MOE` | `32` | Number of expert layers kept on CPU. Lower = more on GPU = faster but uses more VRAM. |
| `LLAMA_ARG_CTX_SIZE` | `131072` | Context window (128k). KV cache uses ~8-10GB with Turbo Quant. |
| `LLAMA_ARG_CACHE_TYPE_K` | `q4_0` | KV cache key quantization. Q4 = minimal quality loss. |
| `LLAMA_ARG_CACHE_TYPE_V` | `q3_0` | KV cache value quantization. Q3 works due to 8:1 GQA ratio. |
| `LLAMA_ARG_NO_MMAP` | `true` | Load model into RAM immediately (no paging delays). |
| `LLAMA_ARG_MLOCK` | `true` | Prevent OS from swapping model to disk. Requires `IPC_LOCK` capability. |

## Memory Distribution (16GB VRAM)

```
┌─────────────────────────────────────┐
│ VRAM (16GB)                         │
├─────────────────────────────────────┤
│ KV Cache (128k): ~8-10GB            │ ← Turbo Quant (Q4/Q3)
│ Model Layers: ~6-8GB                │ ← Controlled by N_GPU_LAYERS
│ Overhead: ~1GB                      │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ System RAM (32GB+ recommended)      │
├─────────────────────────────────────┤
│ Model Experts: ~12-14GB             │ ← Controlled by N_CPU_MOE
│ System overhead: remaining          │
└─────────────────────────────────────┘
```

## Tuning Process

### 1. Deploy and Monitor Initial Setup

```bash
# Deploy
podman kube play kube/llama-server.yaml

# Monitor logs
podman logs -f llama-server-llama-server

# Check VRAM usage (AMD GPU)
watch -n 1 "podman exec llama-server-llama-server cat /sys/class/drm/card*/device/mem_info_vram_used"

# Or for NVIDIA:
# podman exec llama-server-llama-server nvidia-smi
```

### 2. Optimize Expert Distribution

**Goal:** Maximize GPU utilization without OOM.

| Symptom | Action | Effect |
|---------|--------|--------|
| VRAM usage < 14GB | Decrease `N_CPU_MOE` by 2-4 | More experts on GPU → faster inference |
| VRAM usage > 15.5GB | Increase `N_CPU_MOE` by 2-4 | Move experts to RAM → prevent OOM |
| OOM during inference | Increase `N_CPU_MOE` or decrease `N_GPU_LAYERS` | Reduce GPU memory pressure |

**Tuning example:**
```bash
# Edit the deployment
vim kube/llama-server.yaml

# Change N_CPU_MOE from 32 to 30 (more on GPU)
# Or from 32 to 34 (less on GPU)

# Redeploy
podman kube play --down kube/llama-server.yaml
podman kube play kube/llama-server.yaml
```

### 3. Optimize Layer Count

**Goal:** Fill VRAM efficiently after expert allocation is stable.

| `N_GPU_LAYERS` | Approx VRAM (excluding KV) | Use Case |
|----------------|----------------------------|----------|
| 15 | ~5GB | Conservative, max context headroom |
| 20 | ~6-7GB | **Recommended starting point** |
| 25 | ~8-9GB | If KV cache compression working well |

### 4. Context Window Adjustment

If you don't need 128k context:

| Context Size | KV Cache (Turbo Quant) | VRAM freed for layers |
|--------------|------------------------|----------------------|
| 65536 (64k) | ~4-5GB | +4-5GB for model |
| 98304 (96k) | ~6-7GB | +2-3GB for model |
| 131072 (128k) | ~8-10GB | Current config |

Lower context = more VRAM for layers = faster inference.

## Performance Expectations

**With 16GB VRAM and optimized config:**
- **First token latency:** 5-15 seconds (depends on prompt length)
- **Generation speed:** 15-30 tokens/sec (depends on expert distribution)
- **Context limit:** 128k tokens

**Comparison to baseline:**
- All-CPU (0 GPU layers): ~3-8 tokens/sec
- Optimized GPU+CPU: ~15-30 tokens/sec (**3-4x faster**)

## Troubleshooting

### OOM during model load
- Increase `N_CPU_MOE` (e.g., 32 → 36)
- Decrease `N_GPU_LAYERS` (e.g., 20 → 15)
- Reduce `CTX_SIZE` (e.g., 131072 → 65536)

### Slow inference despite GPU
- Check `N_CPU_MOE` isn't too high (experts thrashing between RAM/VRAM)
- Verify `NO_MMAP=true` (preloads model, avoids disk reads)
- Ensure `MLOCK=true` and `IPC_LOCK` capability enabled

### VRAM underutilized (< 12GB used)
- Decrease `N_CPU_MOE` to move more experts to GPU
- Increase `N_GPU_LAYERS` to load more layers

### Memory leaks / slowdown over time
- Verify `MLOCK=true` is working: `podman exec llama-server-llama-server grep Mlocked /proc/meminfo`
- Should show ~12-22GB locked (model + experts in RAM)
- If low, check `IPC_LOCK` capability in pod security context

## Advanced: Alternative Quantizations

For detailed download instructions and switching between quantization variants, see [MODEL-DOWNLOAD.md](MODEL-DOWNLOAD.md).

If Q6 is too large or you want more speed:

| Quantization | Size | Quality | Speed | VRAM freed |
|--------------|------|---------|-------|------------|
| Q4_K_M | ~17GB | Good | Fastest | +3-5GB |
| Q5_K_M | ~19GB | Better | Fast | +1-3GB |
| **Q6_K** | ~22GB | Excellent | Baseline | 0 |
| Q8_0 | ~26GB | Best | Slower | -4GB (may not fit) |

Change `LLAMA_ARG_HF_FILE`:
- `gemma-4-26B-A4B-it-UD-Q4_K_M.gguf`
- `gemma-4-26B-A4B-it-UD-Q5_K_M.gguf`
- `gemma-4-26B-A4B-it-UD-Q6_K.gguf` (current)

## Sampling Configuration

Sampling parameters control how the model generates text. You can set them server-wide or per-request.

### Method 1: Server-Wide Defaults (Environment Variables)

Add to [`llama-server.yaml`](llama-server.yaml) under the `env:` section:

```yaml
# Sampling parameters (Google's recommended baseline for Gemma 4)
- name: LLAMA_ARG_TOP_K
  value: "64"
- name: LLAMA_ARG_TOP_P
  value: "0.95"
- name: LLAMA_ARG_TEMPERATURE
  value: "1.0"
- name: LLAMA_ARG_REPEAT_PENALTY
  value: "1.0"
```

Then restart:
```bash
systemctl --user daemon-reload
systemctl --user restart podman-llama-server
```

### Method 2: Per-Request Parameters (Recommended)

Override sampling in each API request for maximum flexibility:

```bash
curl http://127.0.0.1:11435/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma4-26b-q6-128k",
    "messages": [{"role": "user", "content": "Explain MoE models"}],
    "temperature": 0.7,
    "top_p": 0.95,
    "top_k": 40,
    "repeat_penalty": 1.1,
    "max_tokens": 500
  }'
```

### Available Parameters

| Parameter | Type | Range | Default | Description |
|-----------|------|-------|---------|-------------|
| `temperature` | float | 0.0-2.0 | 1.0 | Randomness (0.0 = deterministic, higher = more random) |
| `top_k` | int | 0+ | 40 | Sample from top-k tokens (0 = disabled) |
| `top_p` | float | 0.0-1.0 | 0.95 | Nucleus sampling (cumulative probability cutoff) |
| `min_p` | float | 0.0-1.0 | 0.05 | Minimum probability threshold |
| `repeat_penalty` | float | 0.0-2.0 | 1.1 | Penalize repeated tokens (1.0 = no penalty) |
| `frequency_penalty` | float | -2.0-2.0 | 0.0 | Penalize frequent tokens |
| `presence_penalty` | float | -2.0-2.0 | 0.0 | Penalize already-seen tokens |
| `max_tokens` | int | 1+ | -1 | Maximum tokens to generate (-1 = unlimited) |
| `seed` | int | any | -1 | Random seed for reproducibility |

### Presets by Use Case

**Creative Writing** (varied, imaginative output):
```json
{
  "temperature": 1.2,
  "top_k": 64,
  "top_p": 0.95,
  "repeat_penalty": 1.15,
  "frequency_penalty": 0.3
}
```

**Code Generation** (focused, syntactically correct):
```json
{
  "temperature": 0.2,
  "top_k": 20,
  "top_p": 0.9,
  "repeat_penalty": 1.05,
  "max_tokens": 2000
}
```

**Factual Q&A** (deterministic, precise):
```json
{
  "temperature": 0.0,
  "top_k": 1,
  "top_p": 1.0,
  "repeat_penalty": 1.0
}
```

**Gemma 4 Recommended Baseline** (Google's defaults):
```json
{
  "temperature": 1.0,
  "top_k": 64,
  "top_p": 0.95,
  "repeat_penalty": 1.0
}
```

**Long-Form Generation** (reduced repetition):
```json
{
  "temperature": 0.8,
  "top_k": 50,
  "top_p": 0.92,
  "repeat_penalty": 1.2,
  "frequency_penalty": 0.5,
  "presence_penalty": 0.3
}
```

### Testing Different Presets

```bash
# Save a test prompt
PROMPT="Explain mixture of experts architecture in detail."

# Test creative settings
curl -s http://127.0.0.1:11435/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"gemma4-26b-q6-128k\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}],
    \"temperature\": 1.2,
    \"top_k\": 64,
    \"max_tokens\": 300
  }" | jq -r '.choices[0].message.content'

# Test precise settings
curl -s http://127.0.0.1:11435/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"gemma4-26b-q6-128k\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}],
    \"temperature\": 0.2,
    \"top_k\": 10,
    \"max_tokens\": 300
  }" | jq -r '.choices[0].message.content'
```

### Parameter Interaction Notes

- **`top_k` + `top_p`**: Both limit the token pool. Use both for fine control, or set one to 0/1.0 to disable.
- **`temperature` = 0.0**: Makes sampling deterministic (same input → same output with same `seed`).
- **High `repeat_penalty`** (>1.3): Can cause incoherent output; use sparingly.
- **`min_p`**: Alternative to `top_p`; filters tokens below absolute probability threshold.
- **`frequency_penalty` vs `presence_penalty`**: Frequency scales with count; presence is binary (used/not used).

## System Requirements

**Minimum:**
- 16GB VRAM GPU with Vulkan 1.2+
- 32GB system RAM (24GB minimum, may struggle)
- 50GB disk space for model storage

**Recommended:**
- 16GB VRAM GPU
- 48GB+ system RAM
- NVMe SSD for model storage

## References

- [llama.cpp MoE optimization](https://github.com/ggml-org/llama.cpp/discussions/5608)
- [Turbo Quant paper](https://arxiv.org/abs/2410.08708) (KV cache compression)
- [Video guide: 35B on 6GB VRAM](../../../import/local%20ai%20ram%20optimization.md)
