#!/usr/bin/env bash
# Start LiteLLM AI proxy for local LLM servers
# Usage: ./scripts/start-litellm.sh [port] [config]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

PORT="${1:-4000}"
CONFIG="${2:-$PROJECT_DIR/configs/litellm-config.yaml}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}          ${GREEN}LiteLLM AI Proxy for Local LLMs${NC}                   ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if llama servers are running
echo -e "${YELLOW}Checking backend servers...${NC}"
for port in 8000 8001 8002; do
    if curl -s "http://localhost:$port/health" > /dev/null 2>&1; then
        echo -e "  ✓ Port $port: ${GREEN}OK${NC}"
    else
        echo -e "  ✗ Port $port: ${YELLOW}Not responding${NC}"
    fi
done
echo ""

echo -e "${GREEN}Starting LiteLLM proxy on port $PORT${NC}"
echo -e "Config: $CONFIG"
echo ""
echo -e "${BLUE}Unified Endpoints:${NC}"
echo "  • Chat:       http://localhost:$PORT/v1/chat/completions"
echo "  • Embeddings: http://localhost:$PORT/v1/embeddings"
echo "  • Rerank:     http://localhost:$PORT/v1/rerank"
echo "  • Models:     http://localhost:$PORT/v1/models"
echo "  • Health:     http://localhost:$PORT/health"
echo ""
echo -e "${BLUE}Model Aliases (OpenAI compatible):${NC}"
echo "  • gpt-4, gpt-4-turbo, gpt-3.5-turbo → qwen3-coder"
echo "  • text-embedding-3-small/large      → qwen3-embed"
echo "  • rerank-english-v3.0               → bge-reranker"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

# Check if litellm is available
if ! command -v litellm &> /dev/null; then
    echo "Error: litellm not found in PATH"
    echo "Install with: pip install litellm"
    echo "Or use: nix develop"
    exit 1
fi

exec litellm --config "$CONFIG" --port "$PORT" --host 0.0.0.0
