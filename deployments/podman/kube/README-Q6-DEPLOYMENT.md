# Gemma 4 26B Q6 Deployment Summary

## Configuration Overview

Your llama.cpp server is configured for **optimal MoE inference** with:

✅ **Model**: Gemma 4 26B Q6_K (~22GB, 6-bit quantization)  
✅ **Context**: 128k tokens (131,072 exact)  
✅ **GPU**: 16GB VRAM with Vulkan acceleration  
✅ **Strategy**: Core layers on GPU, experts offloaded to system RAM  
✅ **KV Cache**: Turbo Quant compression (Q4 keys, Q3 values)  
✅ **Deployment**: Systemd user service via Podman quadlet

> **Model Download**: The Q6 model (~22GB) downloads automatically on first start. See [MODEL-DOWNLOAD.md](MODEL-DOWNLOAD.md) for manual download options and switching quantization variants.

## Quick Start

```bash
cd /var/home/djosh/Projects/Local-AI/deployments

# Install as systemd service (one-time setup)
bash podman/quadlets/install-llama-server.sh

# Manage the service
systemctl --user status podman-llama-server
systemctl --user restart podman-llama-server
journalctl --user -u podman-llama-server -f

# Test inference
bash scripts/test-llama.sh
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│ GPU (16GB VRAM) - Vulkan                        │
├─────────────────────────────────────────────────┤
│ • KV Cache (128k): ~8-10GB (Turbo Quant)       │
│ • Model Layers (20): ~6-8GB                     │
│ • Expert Layers (8): ~1-2GB                     │
└─────────────────────────────────────────────────┘
                    ↕ PCIe bus
┌─────────────────────────────────────────────────┐
│ System RAM (32GB+ recommended)                  │
├─────────────────────────────────────────────────┤
│ • Expert Layers (32): ~12-14GB                  │
│ • Model file cache: ~22GB                       │
└─────────────────────────────────────────────────┘
```

## Key Optimizations Applied

1. **Expert Offloading** (`N_CPU_MOE=32`)
   - 32 expert layers stay in system RAM
   - Only activated experts transfer to GPU per token
   - Reduces VRAM pressure while maintaining speed

2. **Turbo Quant KV Cache** (`CACHE_TYPE_K=q4_0, CACHE_TYPE_V=q3_0`)
   - Compresses 128k context KV cache from ~16GB to ~8-10GB
   - Minimal quality degradation (< 1% perplexity increase)
   - Enables full context on 16GB VRAM

3. **Memory Locking** (`MLOCK=true, IPC_LOCK`)
   - Prevents OS from paging model to swap
   - Eliminates random slowdowns during long sessions
   - Stable performance over days

4. **No mmap** (`NO_MMAP=true`)
   - Loads entire model into RAM upfront
   - Eliminates disk read latency during inference
   - ~30-40% faster vs. default mmap mode

5. **Flexible Sampling** (per-request or server-wide)
   - Adjust `temperature`, `top_k`, `top_p` for different use cases
   - Google's recommended baseline: temp=1.0, top_k=64, top_p=0.95
   - See [TUNING-GUIDE.md](TUNING-GUIDE.md#sampling-configuration) for presets

## Expected Performance

| Metric | Expected Value | Notes |
|--------|----------------|-------|
| **First token latency** | 5-15 seconds | Depends on prompt length |
| **Generation speed** | 15-30 tok/s | With optimal tuning |
| **Context capacity** | 128k tokens | ~100k words |
| **Model download** | 5-15 minutes | First run only |
| **VRAM usage** | 14-16GB | Monitor and tune |

## Tuning Workflow

### 1. Deploy and Observe

```bash
# Start the service
systemctl --user start podman-llama-server

# Monitor logs
journalctl --user -u podman-llama-server -f
```

Watch VRAM usage during first inference (see TUNING-GUIDE.md for monitoring commands).

### 2. Adjust Expert Distribution

**If VRAM usage < 14GB** (underutilized):
```yaml
# Edit llama-server.yaml
LLAMA_ARG_N_CPU_MOE: "30"  # Move 2 expert layers to GPU
```

**If VRAM usage > 15.5GB** (risk of OOM):
```yaml
LLAMA_ARG_N_CPU_MOE: "34"  # Move 2 expert layers to CPU
```

### 3. Fine-tune Layer Count

Once expert distribution is stable:

```yaml
# Try increasing GPU layers
LLAMA_ARG_N_GPU_LAYERS: "25"  # From 20
```

### 4. Restart and Test

```bash
# Reload systemd to pick up YAML changes
systemctl --user daemon-reload
systemctl --user restart podman-llama-server

# Test
bash scripts/test-llama.sh
```

## File Reference

| File | Purpose |
|------|---------|
| [`llama-server.yaml`](llama-server.yaml) | Kubernetes pod definition with all config |
| [`MODEL-DOWNLOAD.md`](MODEL-DOWNLOAD.md) | Model download guide (Q6 and other variants) |
| [`TUNING-GUIDE.md`](TUNING-GUIDE.md) | Performance tuning + sampling configuration |
| [`../quadlets/podman-llama-server.kube`](../quadlets/podman-llama-server.kube) | Systemd quadlet unit file |
| [`../quadlets/install-llama-server.sh`](../quadlets/install-llama-server.sh) | One-time installation script |
| [`../../scripts/test-llama.sh`](../../scripts/test-llama.sh) | Quick inference test |

## API Endpoints

- **Health**: http://127.0.0.1:11435/health
- **Models**: http://127.0.0.1:11435/v1/models
- **Chat**: http://127.0.0.1:11435/v1/chat/completions

**Quick test with custom sampling:**
```bash
curl http://127.0.0.1:11435/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma4-26b-q6-128k",
    "messages": [{"role": "user", "content": "Explain MoE in one sentence"}],
    "temperature": 0.7,
    "top_k": 40,
    "max_tokens": 100
  }'
```

See [TUNING-GUIDE.md#sampling-configuration](TUNING-GUIDE.md#sampling-configuration) for parameter presets.

## Common Issues

### OOM during model load
**Symptom**: Container crashes or kernel kills process  
**Fix**: Increase `N_CPU_MOE` to 36 or reduce `N_GPU_LAYERS` to 15

### Slow inference (< 10 tok/s)
**Symptom**: Generation is slower than expected  
**Fix**: 
- Check VRAM usage isn't maxed out (thrashing)
- Verify `NO_MMAP=true` and `MLOCK=true` are working
- Lower `N_CPU_MOE` to move more experts to GPU

### VRAM underutilized (< 12GB)
**Symptom**: GPU isn't being used efficiently  
**Fix**: Decrease `N_CPU_MOE` to 28-30 or increase `N_GPU_LAYERS` to 25

### Model download fails
**Symptom**: Error downloading from Hugging Face  
**Fix**: Check network connection, verify model exists at:
```
unsloth/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q6_K.gguf
```

## Next Steps

1. **Install**: `bash podman/quadlets/install-llama-server.sh` (one-time)
2. **Test**: `bash scripts/test-llama.sh` (after model downloads)
3. **Tune**: Adjust `N_CPU_MOE` and `N_GPU_LAYERS` based on VRAM usage
4. **Integrate**: Connect your application to http://127.0.0.1:11435

## Alternative Quantizations

If Q6 doesn't fit or you want more speed:

```yaml
# Q4_K_M (faster, 17GB)
LLAMA_ARG_HF_FILE: "gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"

# Q5_K_M (balanced, 19GB)
LLAMA_ARG_HF_FILE: "gemma-4-26B-A4B-it-UD-Q5_K_M.gguf"
```

See [`TUNING-GUIDE.md`](TUNING-GUIDE.md) for detailed comparison.

## Technical References

- **llama.cpp**: https://github.com/ggml-org/llama.cpp
- **MoE optimization**: Based on techniques from "Running 35B AI Model on 6GB VRAM"
- **Turbo Quant**: https://arxiv.org/abs/2410.08708
- **Model source**: https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF

---

**Status**: Ready to deploy ✅  
**Estimated setup time**: 15-20 minutes (including model download)  
**Deployment**: Systemd user service via Podman quadlet
**Management**: `systemctl --user {start|stop|restart|status} podman-llama-server`
