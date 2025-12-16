# ROCm Setup Guide

## Prerequisites

### System Requirements

- Linux kernel 5.15+ (6.x recommended)
- AMD GPU with ROCm support (gfx900+)
- 64-bit x86_64 system

### Supported Distributions

- Ubuntu 22.04, 24.04
- RHEL/Rocky 8.x, 9.x
- NixOS (with ROCm overlay)
- Arch Linux (via AUR)

## Installation

### NixOS

Add to your configuration:

```nix
{
  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
      rocmPackages.clr
      rocmPackages.rocm-runtime
    ];
  };

  # For HIP development
  environment.systemPackages = with pkgs; [
    rocmPackages.hip-runtime-amd
    rocmPackages.rocm-smi
    rocmPackages.hipcc
  ];

  # User groups
  users.users.youruser.extraGroups = [ "video" "render" ];
}
```

### Ubuntu 22.04/24.04

```bash
# Add ROCm repository
wget https://repo.radeon.com/amdgpu-install/6.0.2/ubuntu/jammy/amdgpu-install_6.0.60002-1_all.deb
sudo apt install ./amdgpu-install_6.0.60002-1_all.deb

# Install ROCm
sudo amdgpu-install --usecase=hip,rocm

# Add user to groups
sudo usermod -a -G video,render $USER

# Reboot
sudo reboot
```

### Arch Linux

```bash
# Install from AUR
yay -S rocm-hip-runtime rocm-hip-sdk rocm-smi-lib
```

## Verification

### Check GPU Detection

```bash
# List AMD GPUs
rocm-smi --showallinfo

# Check HIP devices
hipInfo

# Verify driver
lsmod | grep amdgpu
```

### Expected Output (Strix Halo)

```
======================= ROCm System Management Interface =======================
================================= Concise Info =================================
GPU  Temp (DieEdge)  AvgPwr  SCLK    MCLK     Fan  Perf  PwrCap  VRAM%  GPU%
0    45.0c           15.0W   400Mhz  2133Mhz  N/A  auto  120.0W  0%     0%
================================================================================
```

## Environment Variables

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# ROCm path (if not in default location)
export ROCM_PATH=/opt/rocm
export PATH=$PATH:$ROCM_PATH/bin

# HIP settings
export HIP_VISIBLE_DEVICES=0
export HSA_OVERRIDE_GFX_VERSION=11.5.1  # For gfx1151

# Memory optimization
export HSA_ENABLE_SDMA=0
export GPU_MAX_HW_QUEUES=8
export GPU_MAX_HEAP_SIZE=99
export GPU_MAX_ALLOC_PERCENT=99
```

## Architecture-Specific Settings

### gfx1151 (Strix Halo)

```bash
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export AMDGPU_TARGETS=gfx1151
```

### gfx1100 (RX 7900 XTX/XT)

```bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export AMDGPU_TARGETS=gfx1100
```

### Multiple Architectures

For building binaries compatible with multiple GPUs:

```bash
export AMDGPU_TARGETS="gfx1100;gfx1101;gfx1102;gfx1151"
```

## Building llama.cpp

### UMA Build (APUs with Unified Memory)

```bash
cd ~/llama.cpp

cmake -B build-uma \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_HIP=ON \
    -DGGML_HIP_UMA=ON \
    -DAMDGPU_TARGETS=gfx1151 \
    -DCMAKE_C_COMPILER=hipcc \
    -DCMAKE_CXX_COMPILER=hipcc

cmake --build build-uma --config Release -j $(nproc)
```

### Standard ROCm Build (Discrete GPUs)

```bash
cd ~/llama.cpp

cmake -B build-rocm \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS=gfx1100 \
    -DCMAKE_C_COMPILER=hipcc \
    -DCMAKE_CXX_COMPILER=hipcc

cmake --build build-rocm --config Release -j $(nproc)
```

## VRAM Detection Issues

### Problem: ROCm Shows Limited VRAM

On Strix Halo APUs with 96GB VRAM, ROCm may only detect ~26GB.

### Solution 1: UMA Build

The UMA build bypasses explicit VRAM allocation:

```bash
./scripts/build-llama-uma.sh
```

Runtime flags (REQUIRED):
```bash
--no-mmap
--flash-attn on
--cache-type-k q8_0
--cache-type-v q8_0
```

### Solution 2: TTM Parameters

Modify kernel parameters for larger allocations:

```bash
# /etc/modprobe.d/amdgpu-ttm.conf
options amdgpu vm_size=1024
options amdgpu vm_fragment_size=9
options amdgpu mes=1
```

Reboot required.

### Solution 3: Kernel Command Line

Add to GRUB:

```bash
# /etc/default/grub
GRUB_CMDLINE_LINUX="amdgpu.vm_size=1024 amdgpu.mes=1"
```

Run `update-grub` and reboot.

## Debugging

### Check HIP Compilation

```bash
# Test HIP
hipcc --version

# Run sample
/opt/rocm/bin/vectoradd_hip
```

### Debug Logging

```bash
# Enable AMD logging
export AMD_LOG_LEVEL=4

# HIP debug
export HIP_LAUNCH_BLOCKING=1
export AMD_SERIALIZE_KERNEL=3
```

### Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| No GPU found | `hipInfo` shows 0 devices | Check user groups, driver loaded |
| Wrong architecture | Compute errors | Set `HSA_OVERRIDE_GFX_VERSION` |
| OOM | `cudaMalloc failed` | Reduce context, use Q8 KV cache |
| Slow inference | Low tok/s | Check UMA build, flash attention |

## Performance Tuning

### Flash Attention

Always enable flash attention for performance:

```bash
--flash-attn on
```

### KV Cache Quantization

Quantize KV cache to reduce memory:

```bash
--cache-type-k q8_0
--cache-type-v q8_0
```

Saves ~50% KV cache memory with minimal quality loss.

### Batch Size

For throughput, adjust batch size:

```bash
--batch-size 512
--ubatch-size 512
```

### Thread Count

For CPU-heavy operations:

```bash
--threads $(nproc)
--threads-batch $(nproc)
```

## Monitoring Performance

### During Inference

```bash
# GPU utilization
watch -n 0.5 rocm-smi

# Memory bandwidth
rocm-smi --showmeminfo vram

# Process GPU usage
rocm-smi --showpids
```

### Server Metrics

```bash
# Prometheus metrics
curl http://localhost:8000/metrics

# Slots status
curl http://localhost:8000/slots
```
