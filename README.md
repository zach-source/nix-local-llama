# Local LLM Infrastructure

Run large language models locally on AMD APU hardware with ROCm/HIP acceleration.

## Hardware Target

**AMD Ryzen AI Max+ 395 APU (Strix Halo)**
- Architecture: gfx1151
- Unified Memory: 128GB total (configurable split)
- Current Config: 32GB System / 96GB GPU VRAM
- Wave Size: 32

## Supported Backends

| Backend | Use Case | Performance |
|---------|----------|-------------|
| HIP/ROCm + UMA | AMD APUs with unified memory | Best for APUs (~2x vs Vulkan) |
| HIP/ROCm | AMD discrete GPUs | Best for dGPUs |
| Vulkan | Cross-platform fallback | Works everywhere |

## Quick Start

```bash
# 1. Apply ROCm VRAM fix (required for 96GB config)
./scripts/rocm-vram-fix.sh

# 2. Build llama.cpp with UMA support
./scripts/build-llama-uma.sh

# 3. Start a model server
./scripts/start-server.sh devstral

# 4. Benchmark
./scripts/benchmark.sh
```

## Directory Structure

```
local-llama/
├── scripts/           # Build and runtime scripts
│   ├── build-llama-uma.sh
│   ├── build-llama-rocm.sh
│   ├── build-llama-vulkan.sh
│   ├── rocm-vram-fix.sh
│   ├── start-server.sh
│   └── benchmark.sh
├── configs/           # Model and server configurations
│   └── models.yaml
├── systemd/           # Service unit files
│   ├── llama-server@.service
│   └── llama-devstral.service
├── docs/              # Extended documentation
│   ├── hardware.md
│   ├── rocm-setup.md
│   └── troubleshooting.md
└── builds/            # Build artifacts (gitignored)
```

## Models Tested

| Model | Size | Context | VRAM Usage | Notes |
|-------|------|---------|------------|-------|
| Devstral-Small-2-24B-Q4_K_M | 13.3GB | 128K | ~24GB | Good for coding |
| Qwen3-Coder-30B-Q4_K_M | ~17GB | 64K | ~22GB | Alternative coder |

## Key Flags

### UMA Build (AMD APUs)
```bash
cmake -B build-uma \
  -DGGML_HIP=ON \
  -DGGML_HIP_UMA=ON \
  -DAMDGPU_TARGETS=gfx1151
```

### Runtime Flags
```bash
llama-server \
  --model <path> \
  --ctx-size 131072 \        # 128K context
  --n-gpu-layers 999 \       # Offload all layers to GPU
  --flash-attn on \          # Enable flash attention
  --cache-type-k q8_0 \      # Quantized KV cache
  --cache-type-v q8_0 \
  --no-mmap                  # Required for UMA
```

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

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues:
- ROCm VRAM detection issues
- OOM errors
- Port binding conflicts
- Systemd service management

## License

MIT
