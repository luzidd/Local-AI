# Prefill

## What It Is

Every inference call has two distinct phases:

1. **Prefill** — the model processes all input tokens in parallel to build the KV cache
2. **Decode** — the model generates one output token at a time, autoregressively

"Working..." in an agentic harness means prefill is running. No output token has been produced yet.

---

## Prefill vs. Decode

```
┌─────────────────────────────────────────────────────────┐
│  Input (all known tokens)                               │
│  ├── System prompt                                      │
│  ├── Tool schemas                                       │
│  ├── Conversation history                               │
│  ├── Retrieved context                                  │
│  └── User message                ← even one word        │
│                                                         │
│  PREFILL: all tokens processed in one forward pass      │
│  Output: populated KV cache                             │
└─────────────────────────────────────────────────────────┘
          ↓
┌─────────────────────────────────────────────────────────┐
│  DECODE: one token generated per forward pass           │
│  Each pass attends to KV cache + previously generated   │
│  tokens. Repeats until <eos> or max_tokens.             │
└─────────────────────────────────────────────────────────┘
```

The critical difference: prefill is **bounded by compute** (matrix multiplications over all input tokens at once), while decode is **bounded by memory bandwidth** (loading model weights on every single token). On a GPU, both are fast. On a CPU, both are slow — but for different reasons and at different rates.

---

## Why Prefill Is Slow on CPU

On a GPU, thousands of CUDA cores process all input tokens in parallel. The matrix multiply that drives prefill saturates the GPU's compute units and completes in seconds even for large inputs.

On a CPU:

- Far fewer execution units (12 cores vs. thousands of CUDA cores)
- No dedicated tensor cores — matrix multiplies run as general SIMD instructions
- Memory bandwidth to system RAM is high (~50–100 GB/s) but CPU compute throughput is the bottleneck for prefill

Typical rates for Gemma 4 26B Q4 on a 12-core CPU:

| Phase | Typical rate |
|---|---|
| Prefill | 50–150 tok/s |
| Decode | 3–8 tok/s |

A 19,000-token input (system prompt + tools + history) takes **2–6 minutes of prefill** before the first output token appears — regardless of how short the user's message is.

---

## The KV Cache

During prefill, each transformer layer computes **key** and **value** tensors for every input token. These are stored in the **KV cache** so that decode steps can attend to them without recomputing. The KV cache:

- Lives in RAM (CPU inference) or VRAM (GPU inference)
- Grows with both **context length** and **model size**
- Is allocated upfront based on `num_ctx`, not actual usage

For Gemma 4 26B Q4:

| `num_ctx` | Approximate KV cache size |
|---|---|
| 32K | ~3–4 GB |
| 65K | ~6–8 GB |
| 128K | ~12–16 GB |

On a 32 GB host with ~18 GB already consumed by model weights, the usable KV cache budget is roughly 10–14 GB — setting an effective ceiling on `num_ctx`.

---

## Practical Implications for Local CPU Deployments

### The fixed overhead problem

An agentic harness injects a large fixed payload into every request:

```
System prompt     ~2,000–5,000 tokens
Tool schemas      ~10,000–16,000 tokens  (varies by tool count)
Skills / rules    ~1,000–5,000 tokens    (if enabled)
─────────────────────────────────────────
Total overhead    ~13,000–26,000 tokens
```

This overhead is prefilled on **every request**, including the first one with a single-word message. The user message size is irrelevant to prefill time when overhead dominates.

### Sessions matter

Prefill cost is only paid once per session. Subsequent turns in the same session only prefill the **new tokens** (the latest user message + any new context). Keeping sessions alive and continuing conversations is significantly more efficient than starting fresh sessions.

### Reducing prefill time

In order of impact:

1. **Trim tool schemas** — each removed tool saves hundreds to thousands of tokens of prefill per request. Use `--tools` to pass only the tools needed for the task.

2. **Disable skills and rules** — `--no-skills --no-rules` prevents the harness from injecting discovered skill modules and rule files. Can save 1,000–5,000 tokens.

3. **Keep `num_ctx` conservative** — a larger context window does not slow prefill directly, but a larger KV cache increases memory pressure, which can cause the OS to page and dramatically worsen both prefill and decode performance.

4. **Use longer sessions** — amortise the fixed prefill cost across many turns rather than restarting for each task.

5. **Custom system prompt** — replace the harness's default system prompt with a minimal one via `--system-prompt` or `.omp/SYSTEM.md`. The default prompt is verbose and optimised for cloud models with abundant context.

---

## Relationship to Context Window Usage

A harness reporting "58% context used" at session start means 58% of `num_ctx` is consumed by fixed overhead before any user interaction. This percentage directly predicts prefill time: at 32K context with 58% overhead, ~19K tokens are prefilled on turn one regardless of the user message.

---

## Further Reading

- [Dissecting Batching Effects in GPT Inference](https://www.anyscale.com/blog/llm-continuous-batching-a-systematic-study) — Anyscale. Covers how prefill and decode interact with batching strategies; the charts on time-to-first-token vs. batch size make the prefill bottleneck concrete.

- [vLLM: Easy, Fast, and Cheap LLM Serving with PagedAttention](https://blog.vllm.ai/2023/06/20/vllm.html) — vLLM blog. Explains why KV cache memory management determines throughput, and how PagedAttention reduces fragmentation that would otherwise inflate prefill memory pressure.

- [Towards Efficient Generative Large Language Model Serving: A Survey from Algorithms to Systems](https://arxiv.org/abs/2312.15234) — Academic survey (2023). Section 3 covers prefill/decode disaggregation in depth; Section 4 covers KV cache management. Good reference for understanding why the two phases have fundamentally different hardware requirements.

- [LLM Inference Performance Engineering: Best Practices](https://www.databricks.com/blog/llm-inference-performance-engineering-best-practices) — Databricks. Practical framing of prefill vs. decode tradeoffs in production; the TTFT (time to first token) vs. TPOT (time per output token) distinction maps directly to the two phases described here.

- [Splitwise: Efficient Generative LLM Inference Using Phase Splitting](https://arxiv.org/abs/2311.18677) — Microsoft Research (2023). Proposes running prefill and decode on separate hardware pools. Useful background for understanding why the two phases are increasingly treated as distinct workloads at scale.

- [llama.cpp performance discussion — CPU inference benchmarks](https://github.com/ggml-org/llama.cpp/discussions/4167) — GitHub. Community-collected benchmarks for CPU prefill and decode rates across model sizes and quantizations. Useful for calibrating expectations on specific hardware.

