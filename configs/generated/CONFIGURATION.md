# Local LLM Infrastructure Configuration

## Active Configuration

| Service | Model | Port | Context | Enabled |
|---------|-------|------|---------|---------|
| Chat | Devstral-2-123B | 8000 | 262144 | ✓ |
| Embedding | Qwen3-Embedding-8B | 8001 | 8192 | ✓ |
| Reranking | BGE-Reranker-v2-m3 | 8002 | 512 | ✓ |

## Paths

| Setting | Value |
|---------|-------|
| Models Directory | `$HOME/models` |
| llama.cpp Directory | `$HOME/llama.cpp` |
| ROCm Path | `/opt/rocm` |
| Config Directory | `/etc/llama-server` |

## Gateways

| Gateway | Port | Enabled |
|---------|------|---------|
| Envoy | 4001 | ✓ |
| AI Gateway | 4002 | ✗ |
| LiteLLM | 4000 | ✗ |

## Gateway Routes

**Unified Endpoint:** `http://localhost:4001`

| Path | Backend | Timeout |
|------|---------|---------|
| `/v1/chat/completions` | Chat | 600s |
| `/v1/embeddings` | Embedding | 120s |
| `/v1/rerank` | Reranking | 60s |
| `/health` | Chat | 5s |

## OpenAI-Compatible Aliases

**Chat Models:**
gpt-4, gpt-4-turbo, gpt-4o, gpt-3.5-turbo, claude-3-opus, claude-3-sonnet, devstral, devstral-2, mistral-large, devstral, devstral2, mistral-coder

**Embedding Models:**
text-embedding-ada-002, text-embedding-3-small, text-embedding-3-large, qwen3-embed

**Reranking Models:**
rerank-english-v3.0, rerank-multilingual-v3.0, bge-reranker, rerank

## Hardware Profile

**Strix Halo APU**
- GPU Architecture: gfx1151
- VRAM Available: 90GB
- Build Type: rocm

## Quick Start

```bash
# Start all services
nix run .#envoy start

# Test endpoints
nix run .#envoy test

# Chat completion
curl http://localhost:4001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "Hello"}]}'

# Embeddings
curl http://localhost:4001/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model": "text-embedding-ada-002", "input": "Hello world"}'

# Reranking
curl http://localhost:4001/v1/rerank \
  -H "Content-Type: application/json" \
  -d '{"model": "rerank-english-v3.0", "query": "What is AI?", "documents": ["AI is...", "ML is..."]}'
```

