# Local LLM Infrastructure

Run large language models locally on AMD APU hardware with ROCm/HIP acceleration. Nix-based configuration for llama.cpp servers with unified API gateway routing.

## Hardware Target

**AMD Ryzen AI Max+ 395 APU (Strix Halo)**
- Architecture: gfx1151
- Unified Memory: 128GB total (configurable split)
- Current Config: 32GB System / 96GB GPU VRAM
- ROCm Version: 7.1.1 (with rocWMMA flash attention)

## Current Model Stack

| Service | Model | Size | Context | Port |
|---------|-------|------|---------|------|
| **Chat** | Devstral-2-123B Q4_K_M | 75 GB | 256K | 8000 |
| **Embedding** | Qwen3-Embedding-8B Q8 | 8.5 GB | 8K | 8001 |
| **Reranking** | BGE-Reranker-v2-m3 Q8 | 1.2 GB | 512 | 8002 |
| **Gateway** | Envoy Proxy | — | — | 4001 |

Memory: ~89GB total (within 96GB VRAM)

## Features

- **Unified Nix Configuration**: Single source of truth in `nix/llm-config.nix`
- **Envoy API Gateway**: OpenAI-compatible routing with model aliasing
- **Multiple Backends**: Chat, embeddings, and reranking on separate ports
- **Systemd Services**: Production-ready service management
- **Config Generation**: Auto-generate llama.cpp, Envoy, LiteLLM, and systemd configs

## Quick Start

### Using Nix Flake

```bash
# Enter development shell
nix develop

# Show current configuration
nix run .#generate-configs -- show

# Generate all config files
nix run .#generate-configs -- generate

# Start Envoy gateway
nix run .#envoy
```

### Manual Setup

```bash
# 1. Apply ROCm VRAM fix (required for 96GB config)
./scripts/rocm-vram-fix.sh

# 2. Build llama.cpp with ROCm support
./scripts/build-llama-uma.sh

# 3. Download model
huggingface-cli download unsloth/Devstral-2-123B-Instruct-2512-GGUF \
  --include "Devstral-2-123B-Instruct-2512-Q4_K_M.gguf" \
  --local-dir ~/models/

# 4. Start using generated config
source configs/generated/chat.conf
$LLAMA_BIN -m $MODEL_PATH --host $HOST --port $PORT -c $CTX_SIZE $EXTRA_FLAGS
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Client Applications                       │
│         (OpenAI SDK, LangChain, LlamaIndex, etc.)           │
│                                                              │
│   Use any model alias: gpt-4, claude-3-opus, devstral, etc. │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Envoy Gateway (:4001)                        │
│                                                              │
│  /v1/embeddings  ──────────────────────► :8001 (Embedding)  │
│  /v1/rerank      ──────────────────────► :8002 (Reranking)  │
│  /v1/chat/*      ──────────────────────► :8000 (Chat)       │
│  /v1/completions ──────────────────────► :8000 (Chat)       │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  Chat (:8000) │    │ Embed (:8001) │    │Rerank (:8002) │
│  Devstral-2   │    │  Qwen3-Embed  │    │ BGE-Reranker  │
│     123B      │    │      8B       │    │    v2-m3      │
└───────────────┘    └───────────────┘    └───────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    llama.cpp + ROCm 7.1.1                    │
│               AMD Ryzen AI Max+ 395 APU                      │
│                    96GB Unified VRAM                         │
└─────────────────────────────────────────────────────────────┘
```

## OpenAI-Compatible Aliases

All requests go through `http://localhost:4001`:

```bash
export OPENAI_API_BASE=http://localhost:4001/v1
export OPENAI_API_KEY=sk-local  # Any value works
```

| Request Model | Routes To |
|--------------|-----------|
| `gpt-4`, `gpt-4-turbo`, `gpt-4o` | Devstral-2-123B |
| `claude-3-opus`, `claude-3-sonnet` | Devstral-2-123B |
| `devstral`, `devstral-2`, `mistral-large` | Devstral-2-123B |
| `text-embedding-ada-002`, `text-embedding-3-small` | Qwen3-Embed-8B |
| `rerank-english-v3.0`, `bge-reranker` | BGE-Reranker-v2-m3 |

## Configuration System

All configuration is driven from `nix/llm-config.nix`:

```bash
# View active configuration
nix run .#generate-configs -- show

# Generate all configs to configs/generated/
nix run .#generate-configs -- generate

# Install systemd services
nix run .#generate-configs -- install
```

### Generated Files

| File | Purpose |
|------|---------|
| `chat.conf` | llama.cpp server config for chat model |
| `embedding.conf` | llama.cpp server config for embeddings |
| `reranking.conf` | llama.cpp server config for reranker |
| `envoy.yaml` | Envoy gateway routing configuration |
| `litellm-config.yaml` | LiteLLM proxy configuration (alternative) |
| `llama-server-*.service` | Systemd unit files |
| `CONFIGURATION.md` | Human-readable documentation |

### Changing Models

Edit `nix/llm-config.nix` to switch models:

```nix
# In activeConfig.services.chat:
model = modelLibrary.chat.devstral2-123b;     # Current: 123B Q4
# model = modelLibrary.chat.devstral2-24b;    # Faster: 24B Q8
# model = modelLibrary.chat.qwen3-coder-30b;  # Alternative: Qwen3
```

Then regenerate: `nix run .#generate-configs -- generate`

## Available Models

### Chat Models

| Key | Model | Size | SWE-bench | Notes |
|-----|-------|------|-----------|-------|
| `devstral2-123b` | Devstral-2-123B Q4_K_M | 75 GB | 72.2% | Best coding, 256K ctx |
| `devstral2-123b-q5` | Devstral-2-123B Q5_K_M | 88 GB | 72.2% | Higher quality, 64K ctx |
| `devstral2-24b` | Devstral-Small-2 Q8_0 | 25 GB | 68.0% | Fast inference |
| `qwen3-coder-30b` | Qwen3-Coder-30B-A3B Q6_K | 24 GB | — | MoE, good for coding |

### Embedding & Reranking

| Key | Model | Size | Dimensions |
|-----|-------|------|------------|
| `qwen3-embed-8b` | Qwen3-Embedding-8B Q8 | 8.5 GB | 4096 |
| `bge-reranker-v2-m3` | BGE-Reranker-v2-m3 Q8 | 1.2 GB | — |

## Directory Structure

```
local-llama/
├── flake.nix              # Nix flake with apps and packages
├── nix/
│   └── llm-config.nix     # Unified configuration module
├── scripts/               # Build and runtime scripts
│   ├── build-llama-uma.sh
│   ├── build-llama-rocm.sh
│   ├── start-server.sh
│   ├── rocm-vram-fix.sh
│   └── benchmark.sh
├── configs/
│   ├── envoy.yaml         # Active Envoy config
│   ├── aigw-config.yaml   # AI Gateway (K8s style) config
│   └── generated/         # Auto-generated configs
├── systemd/               # Service unit files
└── docs/                  # Extended documentation
```

## Nix Flake Apps

```bash
nix run .#generate-configs  # Generate all configuration files
nix run .#envoy             # Start Envoy gateway
nix run .#litellm           # Start LiteLLM proxy (alternative)
nix run .#firewall          # Manage firewall rules
nix run .#webui             # Start Open WebUI chat interface
nix run .#install           # Install systemd services
```

## Firewall Configuration

```bash
nix run .#firewall enable   # Open ports 4001, 8000-8002
nix run .#firewall disable  # Close ports (localhost only)
nix run .#firewall status   # Show current rules
```

| Port | Service | Description |
|------|---------|-------------|
| 3000 | Open WebUI | Chat interface (optional) |
| 4001 | Envoy Gateway | Main API gateway |
| 8000 | Chat Backend | Devstral-2-123B |
| 8001 | Embedding Backend | Qwen3-Embed-8B |
| 8002 | Reranking Backend | BGE-Reranker |

## Memory Planning

KV Cache formula (Q8 quantization):
```
KV_Cache_GB = ctx_size × n_layers × d_model × 2 × 2 × 0.5 / 1e9
```

For Devstral-2-123B (88 layers):

| Context | KV Cache (Q8) | Model (Q4) | Total |
|---------|---------------|------------|-------|
| 256K | ~14 GB | 75 GB | ~89 GB |
| 128K | ~7 GB | 75 GB | ~82 GB |
| 64K | ~3.5 GB | 75 GB | ~78 GB |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| OOM errors | Reduce `contextSize` in llm-config.nix |
| ROCm shows ~2.5GB VRAM | Add `-fit off` flag, set `GGML_CUDA_ENABLE_UNIFIED_MEMORY=1` |
| Slow inference | Verify all layers on GPU, enable `--flash-attn on` |
| Port in use | `lsof -i :8000` to find process |

See [docs/troubleshooting.md](docs/troubleshooting.md) for more.

## License

MIT
