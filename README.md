# Local LLM Infrastructure

Run large language models locally on AMD APU hardware with ROCm/HIP acceleration.

## Hardware Target

**AMD Ryzen AI Max+ 395 APU (Strix Halo)**
- Architecture: gfx1151
- Unified Memory: 128GB total (configurable split)
- Current Config: 32GB System / 96GB GPU VRAM
- Wave Size: 32

## Features

- **Multiple Model Types**: Chat, Embeddings, and Reranking
- **LiteLLM Proxy**: OpenAI-compatible chat API with model aliasing (gpt-4 → local)
- **Nix Flake**: Reproducible builds and deployment
- **Systemd Services**: Production-ready service management for all models

## Quick Start

### Using Nix Flake (Recommended)

```bash
# Enter development shell
nix develop

# Or run the install script
nix run .#install
```

### Manual Setup

```bash
# 1. Apply ROCm VRAM fix (required for 96GB config)
./scripts/rocm-vram-fix.sh

# 2. Build llama.cpp with UMA support
./scripts/build-llama-uma.sh

# 3. Start model servers
./scripts/start-server.sh devstral

# 4. Start LiteLLM proxy (unified API)
./scripts/start-litellm.sh
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Client Applications                       │
│         (OpenAI SDK, LangChain, LlamaIndex, etc.)           │
└─────────────────────────────────────────────────────────────┘
                              │
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ LiteLLM (:4000) │ │  Embed (:8001)  │ │ Rerank (:8002)  │
│   Chat Proxy    │ │  Qwen3-Embed    │ │  BGE-Reranker   │
│  (gpt-4 alias)  │ │   (direct)      │ │   (direct)      │
└─────────────────┘ └─────────────────┘ └─────────────────┘
            │
            ▼
┌─────────────────┐
│   Chat (:8000)  │
│  Qwen3-Coder    │
│     30B-A3B     │
└─────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────┐
│                    llama.cpp + ROCm                          │
│               AMD Ryzen AI Max+ 395 APU                      │
│                    96GB Unified VRAM                         │
└─────────────────────────────────────────────────────────────┘
```

## Endpoints

### LiteLLM Proxy (Chat Only)
| Endpoint | Port | Model Aliases |
|----------|------|---------------|
| `/v1/chat/completions` | 4000 | gpt-4, gpt-4-turbo, gpt-4o, gpt-3.5-turbo, claude-3-opus, claude-3-sonnet, qwen3-coder |

**Note**: LiteLLM provides OpenAI API compatibility for chat. Use existing OpenAI SDKs with:
```bash
export OPENAI_API_BASE=http://localhost:4000
export OPENAI_API_KEY=sk-local-llm-master
```

### Direct Backend Access (HTTP)
| Service | Port | Endpoint |
|---------|------|----------|
| Chat | 8000 | `http://localhost:8000/v1/chat/completions` |
| Embeddings | 8001 | `http://localhost:8001/v1/embeddings` |
| Reranker | 8002 | `http://localhost:8002/v1/rerank` |

> **Note**: Embeddings and reranking must be accessed directly. LiteLLM has compatibility issues with llama.cpp's embedding response format.

## Directory Structure

```
local-llama/
├── flake.nix              # Nix flake for reproducible builds
├── flake.lock             # Locked dependencies
├── scripts/               # Build and runtime scripts
│   ├── build-llama-uma.sh
│   ├── build-llama-rocm.sh
│   ├── start-server.sh
│   ├── start-litellm.sh   # LiteLLM proxy launcher
│   ├── firewall-update.sh # Firewall rule management
│   └── benchmark.sh
├── configs/               # Model and server configurations
│   ├── models.yaml
│   ├── litellm-config.yaml # LiteLLM routing config
│   ├── qwen3-coder.conf
│   ├── qwen3-embed.conf
│   └── bge-reranker.conf
├── systemd/               # Service unit files
│   ├── llama-server@.service
│   ├── llama-nginx-proxy.service
│   └── litellm-proxy.service
└── docs/                  # Extended documentation
    ├── hardware.md
    ├── rocm-setup.md
    └── troubleshooting.md
```

## Systemd Services

```bash
# Enable services to start on boot
sudo systemctl enable llama-server@qwen3-coder
sudo systemctl enable llama-server@qwen3-embed
sudo systemctl enable llama-server@bge-reranker
sudo systemctl enable llama-nginx-proxy

# Start all services
sudo systemctl start llama-server@qwen3-coder
sudo systemctl start llama-server@qwen3-embed
sudo systemctl start llama-server@bge-reranker
sudo systemctl start llama-nginx-proxy

# Check status
sudo systemctl status llama-server@qwen3-coder

# View logs
journalctl -u llama-server@qwen3-coder -f
```

## Firewall Configuration

To allow network access to LLM services (required for remote clients):

```bash
# Using Nix flake
nix run .#firewall enable    # Open ports 4000, 8000, 8001, 8002
nix run .#firewall disable   # Close ports (localhost only)
nix run .#firewall status    # Show current firewall rules

# Using script directly
./scripts/firewall-update.sh enable
./scripts/firewall-update.sh status
```

Supports UFW (Ubuntu/Debian), firewalld (Fedora/RHEL), and iptables fallback.

| Port | Service | Description |
|------|---------|-------------|
| 4000 | LiteLLM Proxy | Main API gateway (chat) |
| 8000 | Chat Model | Qwen3-Coder backend |
| 8001 | Embeddings | Qwen3-Embed backend |
| 8002 | Reranker | BGE-Reranker backend |

## Models

| Model | Size | Context | Port | Use Case |
|-------|------|---------|------|----------|
| Qwen3-Coder-30B-A3B-Q6_K | ~24GB | 256K | 8000 | Coding, chat |
| Qwen3-Embedding-8B-Q8_0 | ~8GB | 8K | 8001 | Text embeddings |
| BGE-Reranker-v2-m3-Q8_0 | ~0.6GB | 512 | 8002 | Relevance reranking |

## Memory Requirements

KV Cache size formula (Q8 quantization):
```
KV_Cache_GB = (ctx_size * n_layers * d_model * 2 * 2) / (1024^3) * 0.5
```

| Context Size | KV Cache (Q8) | Model (24B Q4) | Total |
|-------------|---------------|----------------|-------|
| 262144 (256K) | ~21.7GB | ~13.3GB | ~35GB |
| 131072 (128K) | ~10.9GB | ~13.3GB | ~24GB |
| 65536 (64K) | ~5.4GB | ~13.3GB | ~19GB |

## Nix Flake Usage

```bash
# Show available outputs
nix flake show

# Enter development shell (includes litellm, jq, curl)
nix develop

# Build packages
nix build .#litellm-config

# Run apps
nix run .#install   # Install systemd services
nix run .#litellm   # Start LiteLLM proxy
```

### NixOS Module (WIP)

```nix
{
  inputs.local-llama.url = "github:user/local-llama";

  # In your NixOS configuration:
  services.llama-server = {
    enable = true;
    rocm.gpuTarget = "gfx1151";
    rocm.umaEnabled = true;

    models.chat = {
      modelFile = "Qwen3-Coder-30B-A3B-Q6_K.gguf";
      port = 8000;
      contextSize = 262144;
    };

    proxy.type = "litellm";
    proxy.cache.enable = true;
  };
}
```

## Why LiteLLM?

LiteLLM provides OpenAI API compatibility for chat completions:
- **Model Aliasing**: Use `gpt-4` or `claude-3-sonnet` aliases with local models
- **Drop-in Replacement**: Works with existing OpenAI SDKs and tools
- **Rate Limiting**: Built-in request rate limiting
- **Usage Tracking**: Monitor token usage and costs

> **Current Limitation**: LiteLLM has compatibility issues with llama.cpp's embedding API response format. For embeddings and reranking, access the backends directly on ports 8001 and 8002.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues:
- ROCm VRAM detection issues
- OOM errors
- Port binding conflicts
- Systemd service management

## License

MIT
