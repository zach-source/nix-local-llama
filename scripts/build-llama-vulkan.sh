#!/usr/bin/env bash
# Build llama.cpp with Vulkan backend
# Cross-platform fallback - works on AMD, NVIDIA, Intel, Apple Silicon

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
BUILD_DIR="${BUILD_DIR:-$LLAMA_DIR/build-vulkan}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[Vulkan]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

check_prereqs() {
    log "Checking prerequisites..."

    if ! command -v cmake &>/dev/null; then
        error "cmake not found"
        exit 1
    fi

    # Check for Vulkan SDK
    if ! command -v vulkaninfo &>/dev/null && [[ -z "${VULKAN_SDK:-}" ]]; then
        warn "vulkaninfo not found and VULKAN_SDK not set"
        warn "Build may fail if Vulkan headers are not installed"
    fi

    if [[ ! -d "$LLAMA_DIR" ]]; then
        log "Cloning llama.cpp..."
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
    fi

    log "Prerequisites OK"
}

build_vulkan() {
    log "Building llama.cpp with Vulkan..."
    log "  Build directory: $BUILD_DIR"

    cd "$LLAMA_DIR"

    if [[ -d "$BUILD_DIR" ]]; then
        warn "Removing existing build directory..."
        rm -rf "$BUILD_DIR"
    fi

    cmake -B "$BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_VULKAN=ON

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

    # List available Vulkan devices
    if command -v vulkaninfo &>/dev/null; then
        log "Available Vulkan devices:"
        vulkaninfo --summary 2>/dev/null | grep -E "deviceName|driverVersion" || true
    fi

    log "Build verification complete"
}

main() {
    log "=== llama.cpp Vulkan Build Script ==="
    log "Cross-platform GPU acceleration"
    echo

    check_prereqs
    build_vulkan
    verify_build

    echo
    log "=== Build Complete ==="
    log "To start a server:"
    echo "  $BUILD_DIR/bin/llama-server \\"
    echo "    --model <path-to-model.gguf> \\"
    echo "    --ctx-size 32768 \\"
    echo "    --n-gpu-layers 999 \\"
    echo "    --flash-attn on"
    echo
    log "Note: Vulkan is slower than HIP/ROCm on AMD GPUs"
    log "      Use build-llama-uma.sh for AMD APUs with unified memory"
}

main "$@"
