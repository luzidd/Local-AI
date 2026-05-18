# Model Download Guide — Gemma 4 26B MoE

This guide covers downloading the Gemma 4 26B MoE model in various quantization formats for llama.cpp.

## Automatic Download (Default)

The llama.cpp server **automatically downloads** the model from Hugging Face when it first starts. No manual steps required.

**Model configured:**
- **Repository**: `unsloth/gemma-4-26B-A4B-it-GGUF`
- **File**: `gemma-4-26B-A4B-it-UD-Q6_K.gguf` (6-bit quantization)
- **Size**: ~22 GB
- **Download time**: 5-15 minutes (depending on internet speed)

The model is cached in a persistent volume (`llama-server-data`) and only downloaded once.

### Monitor Automatic Download

```bash
# Watch download progress in logs
journalctl --user -u podman-llama-server -f

# You'll see output like:
# Downloading model from HuggingFace...
# Downloaded 5.2 GB / 22.1 GB (23%)...
```

---

## Manual Pre-Download (Optional)

If you want to download the model **before** starting the service, or download multiple quantization variants:

### Option 1: Using huggingface-cli

```bash
# Install Hugging Face CLI (if not already installed)
pip install --user huggingface-hub

# Download Q6_K (6-bit, ~22GB) - recommended for 16GB VRAM
huggingface-cli download \
  unsloth/gemma-4-26B-A4B-it-GGUF \
  gemma-4-26B-A4B-it-UD-Q6_K.gguf \
  --local-dir ~/Downloads/gemma4-models \
  --local-dir-use-symlinks False

# The file will be downloaded to:
# ~/Downloads/gemma4-models/gemma-4-26B-A4B-it-UD-Q6_K.gguf
```

### Option 2: Direct Download from Hugging Face

Visit the repository and download directly:
- **URL**: https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/tree/main
- **File**: `gemma-4-26B-A4B-it-UD-Q6_K.gguf`
- Click the filename → "Download" button

**Filename format explained:**
```
gemma-4-26B-A4B-it-UD-Q6_K.gguf
│       │   │   │  │  │  │  └─ File format (GGUF - GPT-Generated Unified Format)
│       │   │   │  │  │  └──── Quantization method (K-quant - improved quality/size)
│       │   │   │  │  └─────── Quantization bits (Q6 = 6-bit weights)
│       │   │   │  └────────── Upload/distribution variant (UD = Unsloth Distribution)
│       │   │   └───────────── Instruction-tuned (it = fine-tuned for chat/instructions)
│       │   └───────────────── Architecture (A4B = Active-4-Billion per token in MoE)
│       └───────────────────── Model size (26B = 26 billion total parameters)
└───────────────────────────── Model family and version (Gemma 4)
```

### Option 3: Pre-download via Container

```bash
# Start a temporary container that just downloads the model
podman run --rm \
  -v llama-server-data:/models:Z \
  -e HF_HOME=/models/huggingface \
  -e LLAMA_ARG_HF_REPO=unsloth/gemma-4-26B-A4B-it-GGUF \
  -e LLAMA_ARG_HF_FILE=gemma-4-26B-A4B-it-UD-Q6_K.gguf \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  --help  # Server exits after showing help, but model is cached

# The model is now in the llama-server-data volume
```

---

## Available Quantization Formats

All variants are available from the same repository: `unsloth/gemma-4-26B-A4B-it-GGUF`

| File | Quantization | Size | Quality | VRAM Usage | Speed | Recommended For |
|------|--------------|------|---------|------------|-------|-----------------|
| `gemma-4-26B-A4B-it-UD-Q4_K_M.gguf` | Q4_K_M (4-bit) | ~17 GB | Good | ~12-14 GB | Fastest | 12GB VRAM |
| `gemma-4-26B-A4B-it-UD-Q5_K_M.gguf` | Q5_K_M (5-bit) | ~19 GB | Better | ~13-15 GB | Fast | 14GB VRAM |
| **`gemma-4-26B-A4B-it-UD-Q6_K.gguf`** | **Q6_K (6-bit)** | **~22 GB** | **Excellent** | **~14-16 GB** | **Baseline** | **16GB VRAM** ✅ |
| `gemma-4-26B-A4B-it-Q8_0.gguf` | Q8_0 (8-bit) | ~26 GB | Best | ~18-20 GB | Slower | 24GB+ VRAM |

**Current configuration uses Q6_K** — optimal balance of quality and VRAM usage for 16GB GPUs.

---

## Switching Quantization Variants

To use a different quantization, edit [`podman/kube/llama-server.yaml`](llama-server.yaml):

### Example: Switch to Q4_K_M (faster, less VRAM)

```yaml
# Change this line:
- name: LLAMA_ARG_HF_FILE
  value: gemma-4-26B-A4B-it-UD-Q4_K_M.gguf  # Was: Q6_K.gguf

# Also update the alias:
- name: LLAMA_ARG_ALIAS
  value: gemma4-26b-q4-128k  # Was: gemma4-26b-q6-128k
```

Then reload the service:

```bash
systemctl --user daemon-reload
systemctl --user restart podman-llama-server
```

The new variant will be downloaded automatically on restart.

---

## Verify Downloaded Model

### Check if model is cached

```bash
# List files in the persistent volume
podman volume inspect llama-server-data --format '{{.Mountpoint}}'

# If running, check inside the container
podman exec llama-server-llama-server \
  ls -lh /models/huggingface/hub/models--unsloth--gemma-4-26B-A4B-it-GGUF/snapshots/*/

# Should show: gemma-4-26B-A4B-it-UD-Q6_K.gguf (~22GB)
```

### Check loaded model via API

```bash
curl -s http://127.0.0.1:11435/v1/models | jq

# Expected output:
# {
#   "data": [
#     {
#       "id": "gemma4-26b-q6-128k",
#       "object": "model",
#       ...
#     }
#   ]
# }
```

---

## Troubleshooting Download Issues

### Download stuck or very slow

```bash
# Check logs
journalctl --user -u podman-llama-server -f

# If download is stuck, restart the service
systemctl --user restart podman-llama-server
```

### Out of disk space

```bash
# Check available space in the volume
df -h $(podman volume inspect llama-server-data --format '{{.Mountpoint}}')

# Q6 requires ~25GB free (22GB model + overhead)
```

### Authentication errors

Some Hugging Face models require authentication. If you see "401 Unauthorized":

```bash
# Set your HF token (get it from huggingface.co/settings/tokens)
export HF_TOKEN="hf_xxxxxxxxxxxxxxxxxxxxx"

# Add to the YAML:
# - name: HF_TOKEN
#   value: "hf_xxxxxxxxxxxxxxxxxxxxx"
```

**Note:** The Gemma 4 26B model from `unsloth/gemma-4-26B-A4B-it-GGUF` is **public** and does not require authentication.

### Verify download integrity

```bash
# Get the file hash from Hugging Face
# Compare with downloaded file
sha256sum ~/Downloads/gemma4-models/gemma-4-26B-A4B-it-UD-Q6_K.gguf

# Or inside the container volume
podman exec llama-server-llama-server sha256sum /models/huggingface/hub/models--*/snapshots/*/gemma-4-26B-A4B-it-UD-Q6_K.gguf
```

---

## Download Multiple Variants

To keep multiple quantization variants cached:

```bash
# Download all common variants
for variant in Q4_K_M Q5_K_M Q6_K Q8_0; do
  huggingface-cli download \
    unsloth/gemma-4-26B-A4B-it-GGUF \
    "gemma-4-26B-A4B-it-UD-${variant}.gguf" \
    --local-dir ~/Downloads/gemma4-models \
    --local-dir-use-symlinks False
done

# Total size: ~84GB for all four variants
```

Then copy them into the volume as needed, or mount a directory with multiple models.

---

## Alternative Models

If Gemma 4 26B is too large, consider these smaller MoE models:

| Model | Quantization | Size | VRAM | Context |
|-------|--------------|------|------|---------|
| Qwen 2.5 14B | Q6_K | ~11 GB | 8-10 GB | 128k |
| Mixtral 8x7B | Q4_K_M | ~26 GB | 14-16 GB | 32k |
| DeepSeek V3 | Q4_K_M | ~18 GB | 12-14 GB | 64k |

Change the `LLAMA_ARG_HF_REPO` and `LLAMA_ARG_HF_FILE` in the YAML to switch models.

---

## References

- **Model Repository**: https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF
- **Quantization Guide**: https://github.com/ggml-org/llama.cpp/blob/master/examples/quantize/README.md
- **llama.cpp Docs**: https://github.com/ggml-org/llama.cpp
- **Hugging Face CLI**: https://huggingface.co/docs/huggingface_hub/guides/download
