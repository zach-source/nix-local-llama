# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Local LLM infrastructure for running large language models on AMD APU hardware with ROCm/HIP acceleration. Primary target is the AMD Ryzen AI Max+ 395 APU (Strix Halo, gfx1151) with 128GB unified memory (96GB configurable as GPU VRAM).

**Current ROCm Version**: 7.1.1 (with rocWMMA support for flash attention)

## Key Commands

### Building llama.cpp

```bash
# UMA build for AMD APUs (recommended for Strix Halo)
./scripts/build-llama-uma.sh

# Standard ROCm build for discrete GPUs
./scripts/build-llama-rocm.sh

# Vulkan fallback for cross-platform
./scripts/build-llama-vulkan.sh
```

Environment variables for builds:
- `LLAMA_DIR` - llama.cpp source location (default: `~/llama.cpp`)
- `GPU_TARGET` - GPU architecture target (default: `gfx1151`)

### Running the Server

```bash
# Start with model preset
./scripts/start-server.sh devstral

# Start with specific options
./scripts/start-server.sh devstral -c xlarge -p 8001 -b uma

# Available model presets: devstral, qwen, qwen-14b, codestral, deepseek, llama3
# Context presets: small (32K), medium (64K), large (128K), xlarge (256K)
```

### Benchmarking

```bash
./scripts/benchmark.sh                          # Default benchmark
./scripts/benchmark.sh single localhost:8000    # Single server
./scripts/benchmark.sh stress localhost:8000 8 120  # Stress test
./scripts/benchmark.sh context localhost:8000   # Context length test
```

### ROCm VRAM Fix

Required when ROCm only detects ~26GB of configured 96GB VRAM:

```bash
./scripts/rocm-vram-fix.sh
```

## Architecture

### Build Variants

| Build | Use Case | Key CMake Flags |
|-------|----------|-----------------|
| `build-rocm` | AMD GPUs/APUs (recommended) | `GGML_HIP=ON`, `GGML_HIP_ROCWMMA_FATTN=ON` |
| `build-vulkan` | Cross-platform fallback | `GGML_VULKAN=ON` |

**Note**: The old `-DGGML_HIP_UMA=ON` compile flag is deprecated. UMA is now enabled at runtime via `GGML_CUDA_ENABLE_UNIFIED_MEMORY=1`.

### UMA Runtime Requirements (Strix Halo)

UMA on Strix Halo APUs requires specific runtime flags:
- `--no-mmap` - Required for unified memory access
- `-fit off` - Bypasses auto-fit which incorrectly detects VRAM
- `--flash-attn on` - Performance optimization (uses rocWMMA)
- `--cache-type-k q8_0 --cache-type-v q8_0` - Quantized KV cache
- `--n-gpu-layers 999` - Force all layers to GPU

### Configuration Files

- `configs/models.yaml` - Model definitions, hardware profiles, memory estimation
- `configs/devstral.conf` - Example systemd service configuration
- `systemd/llama-server@.service` - Template service unit
- `systemd/llama-devstral.service` - Instance-specific service

### Environment Variables

```bash
# ROCm settings (often needed)
export HSA_OVERRIDE_GFX_VERSION=11.5.1  # For gfx1151
export HIP_VISIBLE_DEVICES=0
export AMDGPU_TARGETS=gfx1151
export LD_LIBRARY_PATH=/opt/rocm/lib:/usr/lib/x86_64-linux-gnu

# UMA activation (for APUs)
export GGML_CUDA_ENABLE_UNIFIED_MEMORY=1
export ROCBLAS_USE_HIPBLASLT=1

# Runtime paths
export LLAMA_DIR=~/llama.cpp
export MODELS_DIR=~/models
```

## Memory Planning

KV Cache formula (Q8 quantization):
```
KV_Cache_GB = ctx_size * n_layers * d_model * 2 * 2 * 0.5 / 1e9
```

Quick reference for 24B models:
- 64K context: ~5GB KV + ~13GB model = ~18GB total
- 128K context: ~11GB KV + ~13GB model = ~24GB total
- 256K context: ~22GB KV + ~13GB model = ~35GB total

## Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| OOM errors | Reduce `--ctx-size` or use Q8 KV cache |
| Port 8000 in use | `lsof -i :8000` then kill process or use different port |
| ROCm shows limited VRAM (~2.5GB) | Add `-fit off` flag and ensure `GGML_CUDA_ENABLE_UNIFIED_MEMORY=1` |
| Only 1 layer on GPU | Add `-fit off` and `--n-gpu-layers 999` flags |
| Slow inference (<10 tok/s) | Verify all layers on GPU, enable `--flash-attn on` |
| Wrong GPU architecture | Set `HSA_OVERRIDE_GFX_VERSION=11.5.1` and rebuild |
| Missing ROCm libraries | Set `LD_LIBRARY_PATH=/opt/rocm/lib:/usr/lib/x86_64-linux-gnu` |

See `docs/troubleshooting.md` for detailed solutions.

## ROCm Upgrade

To upgrade ROCm (e.g., from 6.4 to 7.1.1 for rocWMMA support):

```bash
sudo ./scripts/upgrade-rocm-7.sh
```

After upgrade, rebuild llama.cpp:
```bash
./scripts/build-llama-uma.sh
```
