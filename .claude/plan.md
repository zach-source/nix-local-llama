# Build Plan: llama.cpp for AMD Strix Halo (gfx1151)

## Executive Summary

**Critical Finding**: The existing `build-llama-uma.sh` script uses the **deprecated** `-DGGML_HIP_UMA=ON` compile-time flag. This has been replaced with a runtime environment variable `GGML_CUDA_ENABLE_UNIFIED_MEMORY=1` in upstream llama.cpp ([PR #12934](https://github.com/ggml-org/llama.cpp/pull/12934)).

**Recommended Approach**: Single ROCm build with rocWMMA, UMA enabled at runtime.

---

## Phase 1: Verify ROCm Prerequisites

### Check Current Installation
```bash
# ROCm version (need 6.4+ for gfx1151, prefer 7.0+)
rocm-smi --version

# HIP compiler
hipcc --version

# GPU detection
rocm-smi --showproductname

# User groups
groups | grep -E "(video|render)"
```

### Minimum Requirements
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| ROCm | 6.4.2 | 7.0+ |
| Linux Kernel | 6.1+ | 6.16+ |
| linux-firmware | recent | git version |

### If ROCm Not Installed (Fedora)
```bash
# Fedora has ROCm packages
sudo dnf install rocm-hip-devel rocm-smi hipblas rocblas

# Add user to groups
sudo usermod -a -G video,render $USER
# Log out and back in
```

---

## Phase 2: Install rocWMMA for gfx1151

rocWMMA provides significant performance improvements for flash attention.

### Option A: Check if Already Installed
```bash
ls /opt/rocm/include/rocwmma/rocwmma.hpp
```

### Option B: Build from Source (if missing or lacks gfx1151)
```bash
cd ~/workspaces
git clone https://github.com/ROCm/rocWMMA.git
cd rocWMMA

CC=/opt/rocm/bin/amdclang CXX=/opt/rocm/bin/amdclang++ \
cmake -B build . \
  -DROCWMMA_BUILD_TESTS=OFF \
  -DROCWMMA_BUILD_SAMPLES=OFF \
  -DGPU_TARGETS=gfx1151

cmake --build build -j$(nproc)
sudo cmake --install build
```

---

## Phase 3: Clone/Update llama.cpp

```bash
# Fresh clone
git clone https://github.com/ggml-org/llama.cpp.git ~/llama.cpp

# Or update existing
cd ~/llama.cpp && git fetch && git pull
```

---

## Phase 4: Build llama.cpp with Optimal Flags

### Recommended Build Command
```bash
cd ~/llama.cpp

HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
cmake -S . -B build-rocm \
  -DGGML_HIP=ON \
  -DAMDGPU_TARGETS=gfx1151 \
  -DGGML_HIP_ROCWMMA_FATTN=ON \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build-rocm --config Release -j$(nproc)
```

### Build Flags Explained
| Flag | Purpose |
|------|---------|
| `-DGGML_HIP=ON` | Enable ROCm/HIP backend |
| `-DAMDGPU_TARGETS=gfx1151` | Target Strix Halo architecture |
| `-DGGML_HIP_ROCWMMA_FATTN=ON` | Enable rocWMMA flash attention (2x perf) |
| `-DCMAKE_BUILD_TYPE=Release` | Optimized build |

### What NOT to Use
- ~~`-DGGML_HIP_UMA=ON`~~ - **DEPRECATED** (replaced by runtime env var)

---

## Phase 5: Runtime Configuration

### Environment Variables (Required for APU)
```bash
export GGML_CUDA_ENABLE_UNIFIED_MEMORY=1  # Enable unified memory
export ROCBLAS_USE_HIPBLASLT=1            # Better matmul performance
export HIP_VISIBLE_DEVICES=0              # Select GPU device
```

### Server Launch Command
```bash
GGML_CUDA_ENABLE_UNIFIED_MEMORY=1 \
ROCBLAS_USE_HIPBLASLT=1 \
HIP_VISIBLE_DEVICES=0 \
~/llama.cpp/build-rocm/bin/llama-server \
  --model ~/models/Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf \
  --ctx-size 131072 \
  --n-gpu-layers 999 \
  --flash-attn on \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --no-mmap \
  --host 0.0.0.0 \
  --port 8000
```

### Runtime Flags Explained
| Flag | Purpose |
|------|---------|
| `--no-mmap` | **REQUIRED** for unified memory to work |
| `--flash-attn on` | Enable flash attention (must include `on`) |
| `--cache-type-k/v q8_0` | Quantized KV cache (50% memory savings) |
| `-ngl 999` | Offload all layers to GPU |

---

## Phase 6: Verification

### Test GPU Detection
```bash
~/llama.cpp/build-rocm/bin/llama-cli --version
# Should show HIP support
```

### Test Model Loading
```bash
GGML_CUDA_ENABLE_UNIFIED_MEMORY=1 \
~/llama.cpp/build-rocm/bin/llama-cli \
  -m ~/models/small-test-model.gguf \
  -p "Hello" -n 10 -ngl 999 --no-mmap
```

### Benchmark
```bash
GGML_CUDA_ENABLE_UNIFIED_MEMORY=1 \
ROCBLAS_USE_HIPBLASLT=1 \
~/llama.cpp/build-rocm/bin/llama-bench \
  -m ~/models/Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf \
  -ngl 999
```

---

## Known Issues & Workarounds

### 1. ROCm Shows Limited VRAM (~26GB instead of 96GB)
**Solution**: Use `GGML_CUDA_ENABLE_UNIFIED_MEMORY=1` - this bypasses explicit VRAM allocation.

### 2. Slow Model Loading Past 64GB
**Status**: Known issue with ROCm 6.4.2/7-beta ([Issue #15018](https://github.com/ggml-org/llama.cpp/issues/15018))
**Workaround**: Use models <64GB or wait for fix

### 3. rocWMMA Slower at High Context (ROCm 7.0.2+)
**Status**: Performance regression at long contexts
**Workaround**: Disable `-DGGML_HIP_ROCWMMA_FATTN=ON` if issues occur

### 4. KV Cache in System Memory
**Status**: [Issue #18011](https://github.com/ggml-org/llama.cpp/issues/18011) - ROCm may dump KV cache to shared memory
**Impact**: Performance degradation at very long contexts

---

## Performance Expectations

| Configuration | Expected tok/s (24B Q4) |
|--------------|------------------------|
| ROCm + rocWMMA + hipBLASLt | 20-30 |
| ROCm without rocWMMA | 10-15 |
| Vulkan fallback | 10-12 |

---

## Action Items for This Repository

1. **Update `scripts/build-llama-uma.sh`**
   - Rename to `scripts/build-llama-rocm.sh` (single build for both APU/dGPU)
   - Remove deprecated `-DGGML_HIP_UMA=ON`
   - Add `-DGGML_HIP_ROCWMMA_FATTN=ON`

2. **Update `scripts/start-server.sh`**
   - Add `GGML_CUDA_ENABLE_UNIFIED_MEMORY=1` to environment
   - Add `ROCBLAS_USE_HIPBLASLT=1` to environment
   - Keep `--no-mmap` flag

3. **Update documentation**
   - Update `CLAUDE.md` with new build approach
   - Update `docs/rocm-setup.md` with current information

---

## Sources

- [Strix Halo Wiki - llama.cpp with ROCm](https://strixhalo.wiki/AI/llamacpp-with-ROCm)
- [llama.cpp Build Documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
- [PR #12934 - Unified Memory Environment Variable](https://github.com/ggml-org/llama.cpp/pull/12934)
- [ROCm Compatibility - llama.cpp](https://rocm.docs.amd.com/en/latest/compatibility/ml-compatibility/llama-cpp-compatibility.html)
- [Issue #15018 - Slow Loading Past 64GB](https://github.com/ggml-org/llama.cpp/issues/15018)
- [AMD Strix Halo Performance Tracking](https://llm-tracker.info/AMD-Strix-Halo-(Ryzen-AI-Max+-395)-GPU-Performance)
- [rocWMMA gfx1151 Performance](https://github.com/lemonade-sdk/llamacpp-rocm/issues/7)
