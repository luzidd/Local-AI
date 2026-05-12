# Local AI

Documentation and concepts for running LLMs locally on CPU hardware, plus a ready-to-use Docker/Podman deployment.

## Concepts

- System Prompt
- Tools
- Delimiter Tokens
- Modelfile
- [Prefill](prefill.md)

## Quick Start

Get **Gemma 4 26B** running locally in three commands (requires Docker or Podman, ~18 GB disk, recommended 32 GB RAM):

```sh
cd deployments/local-cpu
bash scripts/setup.sh       # one-time: pulls model (~18 GB), builds images
bash scripts/start-omp.sh   # launch the interactive agentic harness
```

See [`deployments/local-cpu/`](deployments/local-cpu/) for full details, config files, and Windows scripts.

### Performance Expectations

- long prefill on CPU
- ~20GB RAM usage at runtime by ollama (model + KV cache)
- ~1–2 tokens/sec on CPU (Gemma 4 26B MoE)

## Layers

The local AI hosting stack is composed of several layers, each responsible for a specific part of the system:

1. **Web UI / API Gateway Layer:** Provides a user interface and API endpoints for interacting with the AI models.
2. **Inference Engine Layer:** Loads models, runs GPU/CPU computations, and streams tokens.
3. **Hardware Layer:** The underlying hardware that executes the computations, such as NVIDIA/AMD GPUs, Apple Silicon, or CPUs.

More info: [Software Stack](software-stack.md)

## Agentic Harness

Handles user input, interface to tools and runs the loop of agentic reasoning. Can be implemented in various languages (Python, Node.js, Go, Rust, etc.) and can run on the same machine or a different one.

Examples:
- VS Code
- OpenCode
- Claude Code

---

## How the Harness Shapes the Prompt

The model never sees raw user messages directly. The harness **assembles the entire context window** before every inference call. The structure sent to the inference engine looks like this:

```
┌─────────────────────────────────────────────────────────────┐
│  System Prompt                                              │
│  ├── Persona / Role definition                              │
│  ├── Behavioral constraints & tone                          │
│  ├── Output format instructions                             │
│  ├── Injected skills (per-task modules)                     │
│  └── Available context summary (e.g. repo, user profile)   │
├─────────────────────────────────────────────────────────────┤
│  Tool / Function Definitions  (JSON schema)                 │
│  ├── Tool name                                              │
│  ├── Tool description  ← model reads this to decide usage   │
│  └── Parameter schema with per-parameter descriptions       │
├─────────────────────────────────────────────────────────────┤
│  Conversation History  (prior turns, token-budgeted)        │
├─────────────────────────────────────────────────────────────┤
│  Retrieved Context  (RAG chunks, file contents, memories)   │
├─────────────────────────────────────────────────────────────┤
│  User Message                                               │
└─────────────────────────────────────────────────────────────┘
```

Each section competes for the same fixed context window. The harness decides what to include, how much space to allocate, and how to order it.

---

## Prompt Layers Explained

### 1. System Prompt

The single highest-leverage input. The model has no memory between calls — everything it "knows about its job" must be restated here on every turn.

**Anatomy of a well-structured system prompt:**

```
## Role
You are a senior backend engineer assistant embedded in a code editor.
Your job is to help the user write, review, and refactor Go and Python code.

## Constraints
- Only suggest changes to the files you are explicitly shown.
- Do not generate code outside the language the user is working in.
- When unsure, ask a clarifying question before writing code.

## Output Format
- Respond in plain prose unless the user asks for code.
- Wrap all code blocks with language-tagged fences.
- Keep answers concise — one paragraph max unless more depth is requested.

## Context
Working repo: {{repo_name}}. Primary language: {{primary_lang}}.
User's skill level: {{skill_level}}.
```

The harness fills in `{{...}}` template variables at runtime, making the system prompt **dynamic per session or per user**.

### 2. Tool Descriptions

The model decides **whether to call a tool and how** entirely from reading the tool's name and description. This is not documentation for humans — it is **model-readable instruction**.

Bad tool description:
```json
{
  "name": "search",
  "description": "Search for things."
}
```

Good tool description:
```json
{
  "name": "search_codebase",
  "description": "Search the current repository for files, functions, or symbols matching a query. Use this when the user asks about existing code, asks you to find something, or before writing code that might duplicate something that already exists. Do NOT use this for web searches.",
  "parameters": {
    "query": {
      "type": "string",
      "description": "Natural language description of what to find. Include relevant symbol names, file types, or concepts."
    }
  }
}
```

Rules for tool descriptions:
- Describe **when to use it**, not just what it does.
- Describe **when NOT to use it** if there's a common confusion risk.
- Write parameter descriptions as if coaching a junior developer.
- Keep names verb-first and specific: `search_codebase`, `create_file`, `run_tests` — not `tool1`, `utility`, `action`.

### 3. Skills (Injected Prompt Modules)

A skill is a **reusable block of instruction** injected into the system prompt conditionally based on the task context. Instead of one giant static system prompt, the harness selects which skills are relevant and composes them at call time.

Example skills:
- `skill_code_review` — instructs the model to check for security, readability, test coverage
- `skill_sql_expert` — adds SQL-specific rules, dialect awareness, query plan reasoning
- `skill_git_workflow` — explains branch conventions, commit message format, PR etiquette
- `skill_explain_to_junior` — adjusts tone and depth when user signals they are learning

The harness selects skills based on:
- The active file type / language
- A detected intent from the user's message
- An explicit user-set persona or mode
- The tools currently enabled

### 4. Delimiter Tokens

Models are trained on data where special tokens mark role boundaries (`<|system|>`, `<|user|>`, `<|assistant|>`, `<|tool_call|>`, etc.). The harness must use the **correct chat template** for the loaded model — getting this wrong silently degrades output quality even if the text looks correct to a human.

Each model family has its own template format:
- **ChatML** (Qwen, Mistral Small, many fine-tunes): `<|im_start|>system ... <|im_end|>`
- **Llama 3**: `<|begin_of_text|><|start_header_id|>system<|end_header_id|> ...`
- **Gemma**: `<start_of_turn>user\n...`

Ollama and vLLM apply the correct chat template automatically from the model's `tokenizer_config.json`. When calling the raw `/v1/chat/completions` API, the inference engine handles template application — but if you call `/v1/completions` (raw text), you must apply the template yourself.

---

## Per-Use-Case Prompt Design

Different use cases need fundamentally different prompt strategies. Do not use a single generic system prompt across all tasks — it either bloats the context or leaves the model without the constraints it needs.

### Use Case Matrix

| Use Case | System Prompt Focus | Key Tools | Context Budget Strategy |
|---|---|---|---|
| **Code assistant** | Language rules, repo conventions, diff format | `search_codebase`, `read_file`, `create_file`, `run_tests` | Maximize file context; minimize history |
| **Research / Q&A** | Citation discipline, uncertainty acknowledgment | `web_search`, `retrieve_document` | Maximize retrieved chunks; keep history short |
| **Data analysis** | Step-by-step reasoning, output as tables/charts | `run_python`, `query_database` | Maximize result context; include schema |
| **DevOps / Infra** | Safety-first: describe before executing, dry-run default | `run_command`, `read_file`, `write_file` | Include current system state; no stale info |
| **Writing assistant** | Tone matching, length discipline, no hallucination | minimal | Maximize document context |
| **Multi-agent orchestrator** | Delegation rules, result synthesis, loop termination | `spawn_agent`, `call_agent`, `collect_results` | Keep coordinator context small; agents handle detail |

### Optimizing for Token Budget

The context window is finite. Every token spent on boilerplate is a token not available for code, documents, or history. Strategies:

- **Front-load critical instructions.** Most models show recency bias in long contexts — place the most important constraints at the **top** of the system prompt, not the bottom.
- **Compress history.** Summarize old turns into a rolling summary instead of keeping every raw message. The harness manages this, not the model.
- **RAG threshold.** Only inject retrieved chunks when retrieval confidence exceeds a threshold. Noisy chunks hurt more than no chunks.
- **Tool thinning.** Only include tools that are relevant to the current task type. A writing assistant doesn't need `run_tests`. More tools = more tokens consumed in every call + higher chance of spurious tool calls.
- **Lazy skill injection.** Skip skill modules that don't apply. A Go file open → inject `skill_go` + `skill_code_review`. A markdown file → inject `skill_writing`. Never inject all skills at once.

### Building Your Setup

A practical approach to building per-use-case configurations:

```
configs/
├── base_system_prompt.md       # shared role + constraints
├── skills/
│   ├── code_review.md
│   ├── sql_expert.md
│   ├── explain_to_junior.md
│   └── devops_safety.md
├── tools/
│   ├── coding_tools.json       # search_codebase, read_file, run_tests
│   ├── research_tools.json     # web_search, retrieve_document
│   └── infra_tools.json        # run_command, read_file, write_file
└── use_cases/
    ├── code_assistant.yaml     # base + [code_review] + coding_tools
    ├── data_analysis.yaml      # base + [sql_expert] + research_tools
    └── devops.yaml             # base + [devops_safety] + infra_tools
```

Each use case config declares:
1. Which skills to inject
2. Which tool set to load
3. Any runtime template variables (repo name, language, user level)
4. Context window budget allocations (history turns, RAG chunk count, file content limits)

The harness reads the active use case at startup (or on mode switch), composes the system prompt, loads the tool schemas, and applies the template before every inference call.