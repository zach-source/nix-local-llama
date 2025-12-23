#!/bin/bash
# llama-ctl.sh - Manage LLM services via systemd user services
#
# Usage:
#   ./scripts/llama-ctl.sh status          - Show service status
#   ./scripts/llama-ctl.sh start-qwen      - Start Qwen3-Coder-30B (fast, 256K ctx)
#   ./scripts/llama-ctl.sh start-devstral  - Start Devstral-24B (slow, 393K ctx)
#   ./scripts/llama-ctl.sh stop            - Stop all services
#   ./scripts/llama-ctl.sh restart         - Restart current model
#   ./scripts/llama-ctl.sh logs [service]  - View logs
#   ./scripts/llama-ctl.sh switch          - Switch between models

set -e

# Required for user systemd in non-interactive shells
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

QWEN_SERVICE="llama-qwen3-coder.service"
DEVSTRAL_SERVICE="llama-devstral.service"
LLAMA70B_SERVICE="llama-llama70b.service"
PROXY_SERVICE="llama-tls-proxy.service"

show_status() {
    echo "=== LLM Service Status ==="
    systemctl --user status $QWEN_SERVICE $DEVSTRAL_SERVICE $LLAMA70B_SERVICE $PROXY_SERVICE 2>/dev/null || true
    echo ""
    echo "=== Endpoints ==="
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "HTTP:  http://localhost:8000  ✓"
    else
        echo "HTTP:  http://localhost:8000  ✗"
    fi
    if curl -sk https://localhost:8443/health > /dev/null 2>&1; then
        echo "HTTPS: https://localhost:8443 ✓"
    else
        echo "HTTPS: https://localhost:8443 ✗"
    fi
}

start_qwen() {
    echo "Starting Qwen3-Coder-30B-A3B (59 tok/s, 256K context)..."
    systemctl --user stop $DEVSTRAL_SERVICE 2>/dev/null || true
    systemctl --user start $QWEN_SERVICE $PROXY_SERVICE
    echo "Waiting for server to initialize..."
    sleep 10
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✓ Server ready at http://localhost:8000"
    else
        echo "✗ Server not responding yet, check: journalctl --user -u $QWEN_SERVICE -f"
    fi
}

start_devstral() {
    echo "Starting Devstral-24B (8.8 tok/s, 393K context)..."
    systemctl --user stop $QWEN_SERVICE $LLAMA70B_SERVICE 2>/dev/null || true
    systemctl --user start $DEVSTRAL_SERVICE $PROXY_SERVICE
    echo "Waiting for server to initialize..."
    sleep 15
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✓ Server ready at http://localhost:8000"
    else
        echo "✗ Server not responding yet, check: journalctl --user -u $DEVSTRAL_SERVICE -f"
    fi
}

start_llama70b() {
    echo "Starting Llama-3.1-70B-Instruct (~15 tok/s, 128K context)..."
    systemctl --user stop $QWEN_SERVICE $DEVSTRAL_SERVICE 2>/dev/null || true
    systemctl --user start $LLAMA70B_SERVICE $PROXY_SERVICE
    echo "Waiting for server to initialize (70B model loads slower)..."
    sleep 30
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✓ Server ready at http://localhost:8000"
    else
        echo "✗ Server not responding yet, check: journalctl --user -u $LLAMA70B_SERVICE -f"
    fi
}

stop_all() {
    echo "Stopping all LLM services..."
    systemctl --user stop $QWEN_SERVICE $DEVSTRAL_SERVICE $LLAMA70B_SERVICE $PROXY_SERVICE 2>/dev/null || true
    echo "✓ All services stopped"
}

restart_current() {
    if systemctl --user is-active --quiet $QWEN_SERVICE; then
        echo "Restarting Qwen3-Coder..."
        systemctl --user restart $QWEN_SERVICE
    elif systemctl --user is-active --quiet $DEVSTRAL_SERVICE; then
        echo "Restarting Devstral..."
        systemctl --user restart $DEVSTRAL_SERVICE
    elif systemctl --user is-active --quiet $LLAMA70B_SERVICE; then
        echo "Restarting Llama-70B..."
        systemctl --user restart $LLAMA70B_SERVICE
    else
        echo "No LLM service is currently running"
        exit 1
    fi
}

show_logs() {
    local service="${1:-$QWEN_SERVICE}"
    if [[ "$service" == "proxy" ]]; then
        service=$PROXY_SERVICE
    elif [[ "$service" == "qwen" ]]; then
        service=$QWEN_SERVICE
    elif [[ "$service" == "devstral" ]]; then
        service=$DEVSTRAL_SERVICE
    elif [[ "$service" == "llama70b" || "$service" == "70b" ]]; then
        service=$LLAMA70B_SERVICE
    fi
    journalctl --user -u "$service" -f
}

switch_model() {
    if systemctl --user is-active --quiet $QWEN_SERVICE; then
        echo "Currently running: Qwen3-Coder"
        echo "Switching to: Devstral"
        start_devstral
    elif systemctl --user is-active --quiet $DEVSTRAL_SERVICE; then
        echo "Currently running: Devstral"
        echo "Switching to: Qwen3-Coder"
        start_qwen
    else
        echo "No model running. Starting Qwen3-Coder (default)..."
        start_qwen
    fi
}

enable_qwen() {
    echo "Enabling Qwen3-Coder to start on boot..."
    systemctl --user enable $QWEN_SERVICE $PROXY_SERVICE
    systemctl --user disable $DEVSTRAL_SERVICE 2>/dev/null || true
    echo "✓ Qwen3-Coder will start on boot"
}

enable_devstral() {
    echo "Enabling Devstral to start on boot..."
    systemctl --user enable $DEVSTRAL_SERVICE $PROXY_SERVICE
    systemctl --user disable $QWEN_SERVICE 2>/dev/null || true
    echo "✓ Devstral will start on boot"
}

case "${1:-status}" in
    status)
        show_status
        ;;
    start-qwen|qwen)
        start_qwen
        ;;
    start-devstral|devstral)
        start_devstral
        ;;
    start-llama70b|llama70b|70b)
        start_llama70b
        ;;
    stop)
        stop_all
        ;;
    restart)
        restart_current
        ;;
    logs)
        show_logs "$2"
        ;;
    switch)
        switch_model
        ;;
    enable-qwen)
        enable_qwen
        ;;
    enable-devstral)
        enable_devstral
        ;;
    *)
        echo "Usage: $0 {status|start-qwen|start-devstral|start-llama70b|stop|restart|logs|switch}"
        echo ""
        echo "Models:"
        echo "  qwen       - Qwen3-Coder-30B-A3B: Fast (59 tok/s), 256K context"
        echo "  devstral   - Devstral-24B: Slow (8.8 tok/s), 393K context"
        echo "  llama70b   - Llama-3.1-70B-Instruct: Dense (~15 tok/s), 128K context"
        echo ""
        echo "Commands:"
        echo "  status          - Show service status and endpoints"
        echo "  start-qwen      - Start Qwen3-Coder (stops other model)"
        echo "  start-devstral  - Start Devstral (stops other model)"
        echo "  start-llama70b  - Start Llama-3.1-70B (stops other model)"
        echo "  stop            - Stop all LLM services"
        echo "  restart         - Restart current model"
        echo "  switch          - Switch between models"
        echo "  logs [service]  - View logs (qwen|devstral|llama70b|proxy)"
        echo "  enable-qwen     - Enable Qwen3-Coder to start on boot"
        echo "  enable-devstral - Enable Devstral to start on boot"
        exit 1
        ;;
esac
