#!/usr/bin/env bash
# Build llama.cpp with HIP/ROCm + UMA support for AMD APUs
# This build enables GGML_HIP_UMA for unified memory access (hipMemAdviseSetCoarseGrain)
# Provides ~2x speedup over Vulkan on AMD APUs with unified memory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
BUILD_DIR="${BUILD_DIR:-$LLAMA_DIR/build-uma}"
GPU_TARGET="${GPU_TARGET:-gfx1151}"  # Strix Halo default

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[UMA]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check prerequisites
check_prereqs() {
    log "Checking prerequisites..."

    if ! command -v hipcc &>/dev/null; then
        error "hipcc not found. Install ROCm first."
        echo "  NixOS: nix-shell -p rocmPackages.hip-runtime-amd"
        echo "  Ubuntu: apt install rocm-hip-runtime-dev"
        exit 1
    fi

    if ! command -v cmake &>/dev/null; then
        error "cmake not found"
        exit 1
    fi

    # Check for llama.cpp source
    if [[ ! -d "$LLAMA_DIR" ]]; then
        log "Cloning llama.cpp..."
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
    fi

    log "Prerequisites OK"
}

# Build with UMA support
build_uma() {
    log "Building llama.cpp with HIP/ROCm + UMA..."
    log "  Target GPU: $GPU_TARGET"
    log "  Build directory: $BUILD_DIR"

    cd "$LLAMA_DIR"

    # Clean previous build if exists
    if [[ -d "$BUILD_DIR" ]]; then
        warn "Removing existing build directory..."
        rm -rf "$BUILD_DIR"
    fi

    # Configure with CMake
    cmake -B "$BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_HIP=ON \
        -DGGML_HIP_UMA=ON \
        -DAMDGPU_TARGETS="$GPU_TARGET" \
        -DCMAKE_C_COMPILER=hipcc \
        -DCMAKE_CXX_COMPILER=hipcc

    # Build
    cmake --build "$BUILD_DIR" --config Release -j "$(nproc)"

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
    log "=== llama.cpp UMA Build Script ==="
    log "For AMD APUs with unified memory (gfx1151 Strix Halo)"
    echo

    check_prereqs
    build_uma
    verify_build

    echo
    log "=== Build Complete ==="
    log "To start a server:"
    echo "  $BUILD_DIR/bin/llama-server \\"
    echo "    --model <path-to-model.gguf> \\"
    echo "    --ctx-size 131072 \\"
    echo "    --n-gpu-layers 999 \\"
    echo "    --flash-attn on \\"
    echo "    --cache-type-k q8_0 \\"
    echo "    --cache-type-v q8_0 \\"
    echo "    --no-mmap"
}

main "$@"
