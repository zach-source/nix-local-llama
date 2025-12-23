#!/usr/bin/env bash
# Build llama.cpp with HIP/ROCm for AMD APUs (gfx1151 Strix Halo)
#
# NOTE: The old -DGGML_HIP_UMA=ON compile-time flag is DEPRECATED.
# Unified memory is now enabled at runtime via:
#   GGML_CUDA_ENABLE_UNIFIED_MEMORY=1
#
# This build creates a standard ROCm binary that works for both discrete GPUs
# and APUs with unified memory - the UMA behavior is controlled at runtime.
#
# See: https://github.com/ggml-org/llama.cpp/pull/12934

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
BUILD_DIR="${BUILD_DIR:-$LLAMA_DIR/build-rocm}"
GPU_TARGET="${GPU_TARGET:-gfx1151}"  # Strix Halo default

# rocWMMA support - enabled by default on ROCm 7.0+ for gfx1151
# Disable with: ENABLE_ROCWMMA=0 ./build-llama-uma.sh
ENABLE_ROCWMMA="${ENABLE_ROCWMMA:-1}"

# HIP Graphs - reduces kernel launch overhead (experimental)
# Disable with: ENABLE_HIP_GRAPHS=0 ./build-llama-uma.sh
ENABLE_HIP_GRAPHS="${ENABLE_HIP_GRAPHS:-1}"

# Native CPU optimizations - uses -march=native for best CPU performance
# Set CPU_ARCH to override (e.g., CPU_ARCH=znver5 for Zen 5)
CPU_ARCH="${CPU_ARCH:-native}"

# Use system cmake to avoid Nix linker issues with ROCm libraries
CMAKE_CMD="${CMAKE_CMD:-/usr/bin/cmake}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[ROCm]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check prerequisites
check_prereqs() {
    log "Checking prerequisites..."

    if ! command -v hipcc &>/dev/null; then
        error "hipcc not found. Install ROCm first."
        echo "  NixOS: nix-shell -p rocmPackages.hip-runtime-amd"
        echo "  Ubuntu: apt install rocm-hip-runtime-dev"
        echo "  Fedora: dnf install rocm-hip-devel"
        exit 1
    fi

    if ! command -v cmake &>/dev/null; then
        error "cmake not found"
        exit 1
    fi

    # Check ROCm version
    local rocm_version
    rocm_version=$(cat /opt/rocm/.info/version 2>/dev/null || echo "unknown")
    log "ROCm version: $rocm_version"

    # Check for llama.cpp source
    if [[ ! -d "$LLAMA_DIR" ]]; then
        log "Cloning llama.cpp..."
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
    fi

    log "Prerequisites OK"
}

# Build with ROCm support
build_rocm() {
    log "Building llama.cpp with HIP/ROCm..."
    log "  Target GPU: $GPU_TARGET"
    log "  Build directory: $BUILD_DIR"

    cd "$LLAMA_DIR"

    # Clean previous build if exists
    if [[ -d "$BUILD_DIR" ]]; then
        warn "Removing existing build directory..."
        rm -rf "$BUILD_DIR"
    fi

    # Set HIP environment
    export HIPCXX="$(/opt/rocm/bin/hipconfig -l)/clang"
    export HIP_PATH="$(/opt/rocm/bin/hipconfig -R)"

    # Build cmake flags
    local cmake_flags=(
        -DCMAKE_BUILD_TYPE=Release
        -DGGML_HIP=ON
        -DAMDGPU_TARGETS="$GPU_TARGET"
        -DLLAMA_CURL=OFF
        -DCMAKE_PREFIX_PATH="/opt/rocm;/usr"
        -DGGML_NATIVE=ON
    )

    # CPU architecture optimizations
    if [[ -n "$CPU_ARCH" ]]; then
        log "CPU architecture: $CPU_ARCH"
        cmake_flags+=("-DCMAKE_CXX_FLAGS=-march=$CPU_ARCH -mtune=$CPU_ARCH")
        cmake_flags+=("-DCMAKE_C_FLAGS=-march=$CPU_ARCH -mtune=$CPU_ARCH")
    fi

    # Optional: rocWMMA for flash attention (requires ROCm 7.0+ for gfx1151)
    if [[ "$ENABLE_ROCWMMA" == "1" ]]; then
        if [[ -f /opt/rocm/include/rocwmma/rocwmma.hpp ]]; then
            log "Enabling rocWMMA flash attention..."
            cmake_flags+=(-DGGML_HIP_ROCWMMA_FATTN=ON)
        else
            warn "rocWMMA not found, skipping ROCWMMA_FATTN"
        fi
    else
        log "rocWMMA disabled (set ENABLE_ROCWMMA=1 to enable, requires ROCm 7.0+)"
    fi

    # Optional: HIP Graphs for reduced kernel launch overhead
    if [[ "$ENABLE_HIP_GRAPHS" == "1" ]]; then
        log "Enabling HIP Graphs..."
        cmake_flags+=(-DGGML_HIP_GRAPHS=ON)
    else
        log "HIP Graphs disabled (set ENABLE_HIP_GRAPHS=1 to enable)"
    fi

    # Configure with CMake (use system cmake to avoid Nix linker issues)
    if [[ ! -x "$CMAKE_CMD" ]]; then
        warn "System cmake not found at $CMAKE_CMD, falling back to cmake"
        CMAKE_CMD="cmake"
    fi
    "$CMAKE_CMD" -S . -B "$BUILD_DIR" "${cmake_flags[@]}"

    # Build
    "$CMAKE_CMD" --build "$BUILD_DIR" --config Release -j "$(nproc)"

    log "Build complete!"
    log "Binary: $BUILD_DIR/bin/llama-server"
}

# Verify build
verify_build() {
    local binary="$BUILD_DIR/bin/llama-server"

    if [[ ! -x "$binary" ]]; then
        error "Build failed - binary not found"
        exit 1
    fi

    log "Verifying build..."
    "$binary" --version 2>/dev/null || true

    # Check for HIP symbols
    if ldd "$binary" 2>/dev/null | grep -q "hip"; then
        log "HIP support: ENABLED"
    else
        warn "HIP symbols not found in binary"
    fi

    log "Build verification complete"
}

main() {
    log "=== llama.cpp ROCm Build Script ==="
    log "For AMD GPUs/APUs (gfx1151 Strix Halo)"
    echo

    check_prereqs
    build_rocm
    verify_build

    echo
    log "=== Build Complete ==="
    echo
    log "For APUs with unified memory, start server with:"
    echo
    echo "  LD_LIBRARY_PATH=/opt/rocm/lib:/usr/lib/x86_64-linux-gnu \\"
    echo "  GGML_CUDA_ENABLE_UNIFIED_MEMORY=1 \\"
    echo "  ROCBLAS_USE_HIPBLASLT=1 \\"
    echo "  HIP_VISIBLE_DEVICES=0 \\"
    echo "  $BUILD_DIR/bin/llama-server \\"
    echo "    --model <path-to-model.gguf> \\"
    echo "    --ctx-size 65536 \\"
    echo "    --n-gpu-layers 999 \\"
    echo "    --flash-attn on \\"
    echo "    --cache-type-k q8_0 \\"
    echo "    --cache-type-v q8_0 \\"
    echo "    --no-mmap \\"
    echo "    -fit off"
    echo
    log "NOTE: --no-mmap and -fit off are REQUIRED for unified memory on Strix Halo"
    log "Or simply use: ./scripts/start-server.sh devstral"
}

main "$@"
