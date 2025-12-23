#!/usr/bin/env bash
# Start llama.cpp server with optimal settings
# Supports different models and configurations
#
# For AMD APUs with unified memory, this script automatically sets:
#   GGML_CUDA_ENABLE_UNIFIED_MEMORY=1  - Enable unified memory access
#   ROCBLAS_USE_HIPBLASLT=1            - Better matrix multiplication performance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
BUILD="${BUILD:-rocm}"  # Changed default from 'uma' to 'rocm'
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
CTX_SIZE="${CTX_SIZE:-131072}"
N_GPU_LAYERS="${N_GPU_LAYERS:-999}"
API_KEY_FILE="${API_KEY_FILE:-}"

# UMA (Unified Memory Architecture) settings for APUs
ENABLE_UMA="${ENABLE_UMA:-1}"  # Enable by default for APU builds

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[START]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Model presets
declare -A MODELS=(
    ["devstral"]="Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf"
    ["devstral-fp16"]="Devstral-Small-2-24B-Instruct-2512-FP16.gguf"
    ["qwen"]="Qwen3-Coder-30B-Q4_K_M.gguf"
    ["qwen-14b"]="Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf"
    ["codestral"]="Codestral-22B-v0.1-Q4_K_M.gguf"
    ["deepseek"]="DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf"
    ["llama3"]="Meta-Llama-3.1-70B-Instruct-Q4_K_M.gguf"
)

# Context presets based on available memory
declare -A CTX_PRESETS=(
    ["small"]="32768"      # 32K - ~3GB KV cache
    ["medium"]="65536"     # 64K - ~5GB KV cache
    ["large"]="131072"     # 128K - ~11GB KV cache
    ["xlarge"]="262144"    # 256K - ~22GB KV cache (requires 96GB+ VRAM)
)

usage() {
    cat << EOF
Usage: $0 [model] [options]

Models:
    devstral        Devstral-Small-2-24B (default)
    qwen            Qwen3-Coder-30B
    qwen-14b        Qwen2.5-Coder-14B
    codestral       Codestral-22B
    deepseek        DeepSeek-Coder-V2-Lite
    llama3          Llama-3.1-70B

    Or provide a path to a .gguf file

Options:
    -b, --build BUILD       Build to use: rocm, vulkan (default: rocm)
    -p, --port PORT         Server port (default: 8000)
    -c, --ctx CTX           Context size or preset: small/medium/large/xlarge
    -k, --api-key FILE      Path to API key file
    --no-uma                Disable unified memory (for discrete GPUs)
    -h, --help              Show this help

Context Presets:
    small   32K context  (~3GB KV cache)
    medium  64K context  (~5GB KV cache)
    large   128K context (~11GB KV cache)
    xlarge  256K context (~22GB KV cache)

Examples:
    $0 devstral                     # Start Devstral with defaults (UMA enabled)
    $0 devstral -c xlarge           # Devstral with 256K context
    $0 qwen -b vulkan -p 8001       # Qwen with Vulkan on port 8001
    $0 qwen --no-uma                # Qwen without unified memory (dGPU)
    $0 ~/models/custom.gguf         # Custom model file

Environment:
    LLAMA_DIR       llama.cpp directory (default: ~/llama.cpp)
    MODELS_DIR      Models directory (default: ~/models)
    BUILD           Default build (rocm/vulkan)
    HOST            Bind address (default: 0.0.0.0)
    PORT            Default port (default: 8000)
    CTX_SIZE        Default context size
    ENABLE_UMA      Enable unified memory (default: 1)
EOF
}

find_model() {
    local model_name="$1"

    # Check if it's a preset
    if [[ -n "${MODELS[$model_name]:-}" ]]; then
        local model_file="${MODELS[$model_name]}"
        local model_path="$MODELS_DIR/$model_file"

        if [[ -f "$model_path" ]]; then
            echo "$model_path"
            return 0
        else
            error "Model file not found: $model_path"
            return 1
        fi
    fi

    # Check if it's a direct path
    if [[ -f "$model_name" ]]; then
        echo "$model_name"
        return 0
    fi

    # Check in models directory
    if [[ -f "$MODELS_DIR/$model_name" ]]; then
        echo "$MODELS_DIR/$model_name"
        return 0
    fi

    # Try with .gguf extension
    if [[ -f "$MODELS_DIR/${model_name}.gguf" ]]; then
        echo "$MODELS_DIR/${model_name}.gguf"
        return 0
    fi

    error "Model not found: $model_name"
    echo "Available presets: ${!MODELS[*]}"
    echo "Or provide a path to a .gguf file"
    return 1
}

find_binary() {
    local build="$1"
    local binary="$LLAMA_DIR/build-${build}/bin/llama-server"

    if [[ -x "$binary" ]]; then
        echo "$binary"
        return 0
    fi

    error "Binary not found: $binary"
    echo "Run: ./scripts/build-llama-${build}.sh"
    return 1
}

start_server() {
    local model_path="$1"
    local binary="$2"

    log "Starting llama-server"
    log "  Build: $BUILD"
    log "  Model: $(basename "$model_path")"
    log "  Context: $CTX_SIZE"
    log "  Port: $PORT"

    # Build command
    local cmd=(
        "$binary"
        --model "$model_path"
        --host "$HOST"
        --port "$PORT"
        --ctx-size "$CTX_SIZE"
        --n-gpu-layers "$N_GPU_LAYERS"
    )

    # Add ROCm/UMA-specific flags
    if [[ "$BUILD" == "rocm" ]]; then
        cmd+=(
            --flash-attn on
            --cache-type-k q8_0
            --cache-type-v q8_0
        )
        # --no-mmap is REQUIRED for unified memory to work
        if [[ "$ENABLE_UMA" == "1" ]]; then
            cmd+=(--no-mmap)
            # -fit off bypasses auto-fit which incorrectly detects VRAM on Strix Halo APUs
            cmd+=(-fit off)
            log "  UMA: enabled (--no-mmap, -fit off)"
        fi
    else
        cmd+=(--flash-attn on)
    fi

    # Add API key if specified
    if [[ -n "$API_KEY_FILE" && -f "$API_KEY_FILE" ]]; then
        cmd+=(--api-key-file "$API_KEY_FILE")
        log "  API Key: enabled"
    fi

    echo
    log "Command: ${cmd[*]}"
    echo

    # Set environment variables for ROCm
    export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.5.1}"
    export HIP_VISIBLE_DEVICES="${HIP_VISIBLE_DEVICES:-0}"

    # ROCm library path (needed for ROCm 7.x)
    if [[ "$BUILD" == "rocm" ]]; then
        export LD_LIBRARY_PATH="/opt/rocm/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
    fi

    # UMA environment variables (for APUs with unified memory)
    if [[ "$ENABLE_UMA" == "1" && "$BUILD" == "rocm" ]]; then
        export GGML_CUDA_ENABLE_UNIFIED_MEMORY=1
        export ROCBLAS_USE_HIPBLASLT=1
        log "UMA environment:"
        log "  GGML_CUDA_ENABLE_UNIFIED_MEMORY=1"
        log "  ROCBLAS_USE_HIPBLASLT=1"
    fi

    # Add library paths for Nix environments (when binary is built with Nix glibc)
    # This is needed when the binary links against Nix glibc but needs system/ROCm libs
    if [[ -d /nix/store ]]; then
        local nix_lib_paths=""
        # Find required libraries in nix store
        for lib_name in numactl elfutils libdrm zstd; do
            local lib_path
            lib_path=$(find /nix/store -maxdepth 2 -type d -name "${lib_name}*" 2>/dev/null | head -1)
            if [[ -n "$lib_path" && -d "${lib_path}/lib" ]]; then
                nix_lib_paths="${nix_lib_paths}:${lib_path}/lib"
            fi
        done
        if [[ -n "$nix_lib_paths" ]]; then
            export LD_LIBRARY_PATH="/opt/rocm/lib:$(dirname "$binary")${nix_lib_paths}:${LD_LIBRARY_PATH:-}"
        fi
    fi

    # Execute
    exec "${cmd[@]}"
}

main() {
    local model_name="devstral"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--build)
                BUILD="$2"
                shift 2
                ;;
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            -c|--ctx)
                if [[ -n "${CTX_PRESETS[$2]:-}" ]]; then
                    CTX_SIZE="${CTX_PRESETS[$2]}"
                else
                    CTX_SIZE="$2"
                fi
                shift 2
                ;;
            -k|--api-key)
                API_KEY_FILE="$2"
                shift 2
                ;;
            --no-uma)
                ENABLE_UMA="0"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                model_name="$1"
                shift
                ;;
        esac
    done

    # Validate build (support 'uma' as alias for 'rocm' for backwards compatibility)
    if [[ "$BUILD" == "uma" ]]; then
        BUILD="rocm"
    fi
    if [[ ! "$BUILD" =~ ^(rocm|vulkan)$ ]]; then
        error "Invalid build: $BUILD"
        echo "Valid builds: rocm, vulkan"
        exit 1
    fi

    # Find model and binary
    local model_path binary

    model_path=$(find_model "$model_name") || exit 1
    binary=$(find_binary "$BUILD") || exit 1

    # Check for port conflicts
    if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
        error "Port $PORT is already in use"
        echo "Check: lsof -i :$PORT"
        exit 1
    fi

    start_server "$model_path" "$binary"
}

main "$@"
