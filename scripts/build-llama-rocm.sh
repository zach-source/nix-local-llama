#!/usr/bin/env bash
# Build llama.cpp with HIP/ROCm support (standard, for discrete GPUs)
# For discrete AMD GPUs without unified memory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
BUILD_DIR="${BUILD_DIR:-$LLAMA_DIR/build-rocm}"
GPU_TARGET="${GPU_TARGET:-gfx1100}"  # RDNA3 default (7900 XTX)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[ROCm]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Common GPU targets:
# gfx900  - Vega 56/64
# gfx906  - Radeon VII
# gfx908  - MI100
# gfx90a  - MI200 series
# gfx1010 - RX 5600/5700
# gfx1030 - RX 6800/6900
# gfx1100 - RX 7900 XTX/XT
# gfx1101 - RX 7800/7700
# gfx1102 - RX 7600
# gfx1151 - Strix Halo APU (use build-llama-uma.sh instead)

check_prereqs() {
    log "Checking prerequisites..."

    if ! command -v hipcc &>/dev/null; then
        error "hipcc not found. Install ROCm first."
        exit 1
    fi

    if ! command -v cmake &>/dev/null; then
        error "cmake not found"
        exit 1
    fi

    if [[ ! -d "$LLAMA_DIR" ]]; then
        log "Cloning llama.cpp..."
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
    fi

    log "Prerequisites OK"
}

build_rocm() {
    log "Building llama.cpp with HIP/ROCm..."
    log "  Target GPU: $GPU_TARGET"
    log "  Build directory: $BUILD_DIR"

    cd "$LLAMA_DIR"

    if [[ -d "$BUILD_DIR" ]]; then
        warn "Removing existing build directory..."
        rm -rf "$BUILD_DIR"
    fi

    cmake -B "$BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_HIP=ON \
        -DAMDGPU_TARGETS="$GPU_TARGET" \
        -DCMAKE_C_COMPILER=hipcc \
        -DCMAKE_CXX_COMPILER=hipcc

    cmake --build "$BUILD_DIR" --config Release -j "$(nproc)"

    log "Build complete!"
    log "Binary: $BUILD_DIR/bin/llama-server"
}

verify_build() {
    local binary="$BUILD_DIR/bin/llama-server"

    if [[ ! -x "$binary" ]]; then
        error "Build failed - binary not found"
        exit 1
    fi

    log "Verifying build..."
    "$binary" --version 2>/dev/null || true
    log "Build verification complete"
}

main() {
    log "=== llama.cpp ROCm Build Script ==="
    log "For AMD discrete GPUs"
    echo

    check_prereqs
    build_rocm
    verify_build

    echo
    log "=== Build Complete ==="
    log "To start a server:"
    echo "  $BUILD_DIR/bin/llama-server \\"
    echo "    --model <path-to-model.gguf> \\"
    echo "    --ctx-size 32768 \\"
    echo "    --n-gpu-layers 999 \\"
    echo "    --flash-attn on"
}

main "$@"
