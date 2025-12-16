# Hardware Configuration

## Target Hardware: AMD Ryzen AI Max+ 395 APU (Strix Halo)

### Specifications

| Component | Value |
|-----------|-------|
| Architecture | gfx1151 (RDNA 3.5) |
| Compute Units | 40 |
| Wave Size | 32 |
| Total Memory | 128GB Unified |
| Memory Config | 32GB System / 96GB GPU VRAM |
| Memory Type | LPDDR5X-8533 |
| Memory Bandwidth | ~273 GB/s |

### BIOS Settings

The VRAM allocation is configured in BIOS:

1. Enter BIOS (usually F2/DEL during boot)
2. Navigate to: Advanced → AMD CBS → NBIO Common Options
3. Set "UMA Frame Buffer Size" to desired allocation:
   - 96GB for maximum model size
   - 64GB for balanced configuration
   - 32GB for more system RAM

### GPU Architecture Notes

**gfx1151 (Strix Halo)** is part of the RDNA 3.5 family:

- **Unified Memory**: CPU and GPU share the same physical memory
- **No VMM**: Virtual Memory Management not available (requires NO_VMM workarounds)
- **UMA Optimization**: GGML_HIP_UMA enables `hipMemAdviseSetCoarseGrain` for efficient unified memory access

### Comparison with Discrete GPUs

| Feature | Strix Halo APU | RX 7900 XTX |
|---------|---------------|-------------|
| VRAM | 96GB (unified) | 24GB (dedicated) |
| Bandwidth | ~273 GB/s | ~960 GB/s |
| Best For | Large models, long context | Fast inference, smaller models |
| Build | UMA | ROCm |

### Memory Hierarchy for LLM Inference

```
┌─────────────────────────────────────────┐
│        128GB Unified Memory Pool        │
├─────────────────────────────────────────┤
│  System RAM (32GB)  │  GPU VRAM (96GB)  │
├─────────────────────┼───────────────────┤
│  - OS & Apps        │  - Model weights  │
│  - llama-server     │  - KV cache       │
│  - Page cache       │  - Compute buffers│
└─────────────────────┴───────────────────┘
```

### Thermal Considerations

The Ryzen AI Max+ 395 is a high-TDP chip (up to 120W). For sustained LLM inference:

- Ensure adequate cooling (laptop or desktop)
- Monitor with: `sensors` or `rocm-smi`
- Consider thermal throttling at sustained loads

### ROCm Compatibility

- **ROCm Version**: 6.0+ recommended
- **HIP Version**: Match ROCm version
- **Known Issues**:
  - VRAM detection may show only ~26GB initially
  - Use TTM parameters or UMA build for full access
  - See `scripts/rocm-vram-fix.sh` for workarounds

## Other Supported Hardware

### AMD Discrete GPUs (ROCm)

| GPU | Architecture | VRAM | Best Build |
|-----|-------------|------|------------|
| RX 7900 XTX | gfx1100 | 24GB | rocm |
| RX 7900 XT | gfx1100 | 20GB | rocm |
| RX 7800 XT | gfx1101 | 16GB | rocm |
| RX 7600 | gfx1102 | 8GB | rocm |
| RX 6900 XT | gfx1030 | 16GB | rocm |

### Vulkan Fallback

Any GPU with Vulkan 1.2+ support:
- AMD RDNA/RDNA2/RDNA3
- NVIDIA Turing/Ampere/Ada
- Intel Arc
- Apple Silicon (MoltenVK)

Build with: `./scripts/build-llama-vulkan.sh`

## Memory Planning

### Model Size Reference

| Model | Q4_K_M | FP16 |
|-------|--------|------|
| 7B | ~4GB | ~14GB |
| 14B | ~8GB | ~28GB |
| 22B | ~12GB | ~44GB |
| 24B | ~13GB | ~48GB |
| 30B | ~17GB | ~60GB |
| 70B | ~40GB | ~140GB |

### KV Cache Size (Q8 Quantization)

| Context | ~24B Model | ~30B Model | ~70B Model |
|---------|-----------|-----------|-----------|
| 32K | ~2.7GB | ~3.4GB | ~8GB |
| 64K | ~5.4GB | ~6.8GB | ~16GB |
| 128K | ~10.9GB | ~13.6GB | ~32GB |
| 256K | ~21.7GB | ~27.2GB | ~64GB |

### Total Memory Requirements

For Devstral-24B Q4_K_M with 128K context:
- Model: ~13.3GB
- KV Cache (Q8): ~10.9GB
- Overhead: ~2GB
- **Total**: ~26GB

For Devstral-24B Q4_K_M with 256K context:
- Model: ~13.3GB
- KV Cache (Q8): ~21.7GB
- Overhead: ~2GB
- **Total**: ~37GB

## Monitoring

### ROCm SMI

```bash
# Watch GPU utilization
watch -n 1 rocm-smi

# Show VRAM info
rocm-smi --showmeminfo vram

# Show temperature
rocm-smi --showtemp
```

### System Memory

```bash
# Overall memory
free -h

# Per-process GPU memory
rocm-smi --showpids
```

### Inference Monitoring

```bash
# Server metrics endpoint
curl http://localhost:8000/metrics

# Health check
curl http://localhost:8000/health
```
