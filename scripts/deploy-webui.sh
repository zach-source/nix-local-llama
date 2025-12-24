#!/usr/bin/env bash
# Deploy Open WebUI chat interface for LiteLLM proxy
#
# Usage:
#   ./scripts/deploy-webui.sh [start|stop|status|logs]
#
# Open WebUI provides a ChatGPT-like interface for your local LLM

set -euo pipefail

CONTAINER_NAME="open-webui"
IMAGE="ghcr.io/open-webui/open-webui:main"
WEBUI_PORT="${WEBUI_PORT:-3000}"
LITELLM_URL="${LITELLM_URL:-http://localhost:4000/v1}"
LITELLM_KEY="${LITELLM_KEY:-sk-local-llm-master}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
}

start_webui() {
    check_docker

    # Check if already running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "Open WebUI is already running"
        show_status
        return 0
    fi

    # Remove stopped container if exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Removing stopped container..."
        docker rm "$CONTAINER_NAME" >/dev/null
    fi

    log_info "Starting Open WebUI on port ${WEBUI_PORT}..."
    log_info "Connecting to LiteLLM at ${LITELLM_URL}"

    docker run -d --name "$CONTAINER_NAME" \
        --network host \
        -v open-webui-data:/app/backend/data \
        -e OPENAI_API_BASE_URL="$LITELLM_URL" \
        -e OPENAI_API_KEY="$LITELLM_KEY" \
        -e WEBUI_AUTH=false \
        -e PORT="$WEBUI_PORT" \
        --restart unless-stopped \
        "$IMAGE" >/dev/null

    log_info "Waiting for startup..."
    sleep 5

    # Check if healthy
    for i in {1..12}; do
        if curl -s "http://localhost:${WEBUI_PORT}" >/dev/null 2>&1; then
            echo ""
            log_success "Open WebUI is running!"
            echo ""
            echo -e "  ${GREEN}URL:${NC} http://localhost:${WEBUI_PORT}"
            echo ""
            echo "Available models (via LiteLLM):"
            echo "  - gpt-4, gpt-4-turbo, gpt-4o, gpt-3.5-turbo"
            echo "  - claude-3-opus, claude-3-sonnet"
            echo "  - qwen3-coder"
            echo ""
            return 0
        fi
        echo -n "."
        sleep 5
    done

    log_warn "WebUI may still be initializing. Check status with: $0 status"
}

stop_webui() {
    check_docker

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Stopping Open WebUI..."
        docker stop "$CONTAINER_NAME" >/dev/null
        docker rm "$CONTAINER_NAME" >/dev/null
        log_success "Open WebUI stopped"
    else
        log_warn "Open WebUI is not running"
    fi
}

show_status() {
    check_docker

    echo ""
    log_info "Open WebUI Status:"
    echo ""

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        local status health
        status=$(docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Status}}")
        echo -e "  Container: ${GREEN}Running${NC}"
        echo -e "  Status:    ${status}"
        echo -e "  Port:      ${WEBUI_PORT}"
        echo -e "  URL:       http://localhost:${WEBUI_PORT}"
        echo ""

        # Check if responding
        if curl -s "http://localhost:${WEBUI_PORT}" >/dev/null 2>&1; then
            echo -e "  Health:    ${GREEN}Healthy${NC}"
        else
            echo -e "  Health:    ${YELLOW}Starting...${NC}"
        fi
    else
        echo -e "  Container: ${RED}Not running${NC}"
        echo ""
        echo "  Start with: $0 start"
    fi
    echo ""
}

show_logs() {
    check_docker

    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker logs -f "$CONTAINER_NAME"
    else
        log_error "Open WebUI container not found"
        exit 1
    fi
}

update_webui() {
    check_docker

    log_info "Pulling latest Open WebUI image..."
    docker pull "$IMAGE"

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Restarting with new image..."
        stop_webui
        start_webui
    else
        log_success "Image updated. Start with: $0 start"
    fi
}

show_help() {
    echo "Open WebUI Deployment Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start   Start Open WebUI (default)"
    echo "  stop    Stop Open WebUI"
    echo "  status  Show container status"
    echo "  logs    Follow container logs"
    echo "  update  Pull latest image and restart"
    echo ""
    echo "Environment variables:"
    echo "  WEBUI_PORT   Port for web interface (default: 3000)"
    echo "  LITELLM_URL  LiteLLM API URL (default: http://localhost:4000/v1)"
    echo "  LITELLM_KEY  API key (default: sk-local-llm-master)"
}

# Main
case "${1:-start}" in
    start)
        start_webui
        ;;
    stop)
        stop_webui
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    update)
        update_webui
        ;;
    -h|--help|help)
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
