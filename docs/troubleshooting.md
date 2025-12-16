# Troubleshooting Guide

## Common Issues

### 1. Out of Memory (OOM)

**Symptom:**
```
ggml_backend_cuda_buffer_type_alloc_buffer: allocating 21760.00 MiB on device 0: cudaMalloc failed: out of memory
alloc_tensor_range: failed to allocate ROCm0 buffer
llama_init_from_model: failed to initialize the context: failed to allocate buffer for kv cache
```

**Causes:**
- Context size too large for available VRAM
- Model + KV cache exceeds VRAM
- Other processes using GPU memory

**Solutions:**

1. **Reduce context size:**
   ```bash
   # Instead of 262144 (256K), use 131072 (128K)
   --ctx-size 131072
   ```

2. **Use quantized KV cache:**
   ```bash
   --cache-type-k q8_0
   --cache-type-v q8_0
   ```

3. **Check memory usage:**
   ```bash
   rocm-smi --showmeminfo vram
   ```

4. **Kill other GPU processes:**
   ```bash
   # Find processes
   rocm-smi --showpids

   # Kill if needed
   kill <pid>
   ```

**Memory Reference:**
| Context | Model 24B | KV Cache (Q8) | Total |
|---------|-----------|---------------|-------|
| 256K | 13GB | 22GB | 35GB |
| 128K | 13GB | 11GB | 24GB |
| 64K | 13GB | 5GB | 18GB |

---

### 2. Port Already in Use

**Symptom:**
```
couldn't bind HTTP server socket, hostname: 0.0.0.0, port: 8000
```

**Solutions:**

1. **Find what's using the port:**
   ```bash
   lsof -i :8000
   # or
   ss -tlnp | grep 8000
   ```

2. **Kill the process:**
   ```bash
   kill $(lsof -t -i :8000)
   ```

3. **Disable systemd services:**
   ```bash
   # System service
   sudo systemctl stop llama-server.service
   sudo systemctl disable llama-server.service
   sudo systemctl mask llama-server.service  # Prevent restart

   # User service
   systemctl --user stop llama-devstral.service
   systemctl --user disable llama-devstral.service
   ```

4. **Stop Docker containers:**
   ```bash
   docker ps | grep llama
   docker stop <container_id>
   ```

5. **Use different port:**
   ```bash
   --port 8001
   ```

---

### 3. Flash Attention Flag Error

**Symptom:**
```
error while handling argument "--flash-attn": error: unknown value for --flash-attn: '--cache-type-k'
```

**Cause:**
New llama.cpp versions require explicit value for `--flash-attn`.

**Solution:**
```bash
# Old syntax (broken)
--flash-attn

# New syntax (correct)
--flash-attn on
```

Valid values: `on`, `off`, `auto`

---

### 4. ROCm VRAM Detection Limited

**Symptom:**
ROCm shows only ~26GB of configured 96GB VRAM.

```
llama_model_load_from_file_impl: using device ROCm0 (AMD Radeon Graphics) - 26236 MiB free
```

**Solutions:**

1. **Use UMA build** (recommended for APUs):
   ```bash
   ./scripts/build-llama-uma.sh
   ```

2. **Required runtime flags:**
   ```bash
   --no-mmap
   --flash-attn on
   --cache-type-k q8_0
   --cache-type-v q8_0
   ```

3. **TTM kernel parameters:**
   ```bash
   sudo ./scripts/rocm-vram-fix.sh --ttm
   # Reboot required
   ```

4. **Check actual allocation:**
   The UMA build can use unified memory beyond the reported VRAM.

---

### 5. No GPU Detected

**Symptom:**
```
hipInfo shows 0 devices
```

**Solutions:**

1. **Check driver loaded:**
   ```bash
   lsmod | grep amdgpu
   ```

2. **Add user to groups:**
   ```bash
   sudo usermod -a -G video,render $USER
   # Log out and back in
   ```

3. **Check device permissions:**
   ```bash
   ls -la /dev/dri/
   ls -la /dev/kfd
   ```

4. **Verify ROCm installation:**
   ```bash
   rocm-smi --showallinfo
   ```

---

### 6. Slow Inference Performance

**Symptom:**
Getting < 10 tok/s when expecting 20-30 tok/s.

**Solutions:**

1. **Ensure GPU offload:**
   ```bash
   --n-gpu-layers 999
   ```

2. **Enable flash attention:**
   ```bash
   --flash-attn on
   ```

3. **Check for thermal throttling:**
   ```bash
   watch -n 1 rocm-smi --showtemp
   ```

4. **Verify using correct build:**
   ```bash
   # UMA build for APUs
   ~/llama.cpp/build-uma/bin/llama-server --version

   # ROCm build for discrete GPUs
   ~/llama.cpp/build-rocm/bin/llama-server --version
   ```

5. **Check for Vulkan fallback:**
   Look for `Vulkan` in startup logs. If using Vulkan instead of HIP, rebuild.

---

### 7. Wrong GPU Architecture

**Symptom:**
```
HIP error: invalid device function
```

**Cause:**
Binary built for wrong GPU architecture.

**Solution:**

1. **Check your GPU:**
   ```bash
   rocm-smi --showproductname
   # or
   dmesg | grep -i gfx
   ```

2. **Set correct target:**
   ```bash
   # For Strix Halo
   export AMDGPU_TARGETS=gfx1151

   # For RX 7900 XTX
   export AMDGPU_TARGETS=gfx1100
   ```

3. **Rebuild:**
   ```bash
   rm -rf build-uma
   ./scripts/build-llama-uma.sh
   ```

4. **Set runtime override:**
   ```bash
   export HSA_OVERRIDE_GFX_VERSION=11.5.1  # For gfx1151
   ```

---

### 8. Systemd Service Won't Stay Stopped

**Symptom:**
Service restarts automatically after stopping.

**Solution:**

1. **Mask the service (prevents restart):**
   ```bash
   sudo systemctl mask llama-server.service
   ```

2. **Check for multiple services:**
   ```bash
   systemctl list-units | grep llama
   systemctl --user list-units | grep llama
   ```

3. **Check for timers:**
   ```bash
   systemctl list-timers | grep llama
   ```

---

### 9. Model Loading Errors

**Symptom:**
```
error loading model: unable to load model
```

**Solutions:**

1. **Verify model file exists:**
   ```bash
   ls -la ~/models/
   ```

2. **Check file integrity:**
   ```bash
   sha256sum model.gguf
   ```

3. **Ensure correct format:**
   - Must be GGUF format (not GGML)
   - Quantization must match expected

4. **Check disk space:**
   ```bash
   df -h
   ```

---

### 10. API Key Issues

**Symptom:**
```
401 Unauthorized
```

**Solutions:**

1. **Check key file exists and has content:**
   ```bash
   cat ~/certs/llama-api.key
   ```

2. **Verify flag syntax:**
   ```bash
   --api-key-file ~/certs/llama-api.key
   ```

3. **Test without key:**
   Remove `--api-key-file` flag temporarily.

---

## Diagnostic Commands

### Quick Health Check

```bash
# 1. Check ROCm
rocm-smi --showallinfo

# 2. Check memory
free -h
rocm-smi --showmeminfo vram

# 3. Check processes
ps aux | grep llama
rocm-smi --showpids

# 4. Check ports
ss -tlnp | grep 800

# 5. Check services
systemctl status llama-server.service
systemctl --user status llama-devstral.service

# 6. Check logs
journalctl -u llama-server -f
```

### Full Diagnostic Script

```bash
#!/usr/bin/env bash
echo "=== System Info ==="
uname -a

echo -e "\n=== ROCm Version ==="
rocm-smi --version 2>/dev/null || echo "ROCm not found"

echo -e "\n=== GPU Info ==="
rocm-smi --showproductname 2>/dev/null || echo "No GPU detected"

echo -e "\n=== VRAM Status ==="
rocm-smi --showmeminfo vram 2>/dev/null || echo "Cannot query VRAM"

echo -e "\n=== Memory ==="
free -h

echo -e "\n=== llama-server Processes ==="
ps aux | grep llama-server | grep -v grep

echo -e "\n=== Port 8000 ==="
lsof -i :8000 2>/dev/null || echo "Port 8000 free"

echo -e "\n=== Environment ==="
echo "HIP_VISIBLE_DEVICES: ${HIP_VISIBLE_DEVICES:-not set}"
echo "HSA_OVERRIDE_GFX_VERSION: ${HSA_OVERRIDE_GFX_VERSION:-not set}"
```

## Getting Help

1. Check llama.cpp issues: https://github.com/ggerganov/llama.cpp/issues
2. ROCm documentation: https://rocm.docs.amd.com/
3. AMD community forums
