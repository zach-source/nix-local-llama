#!/usr/bin/env bash
# Deploy LLM stack to k0s cluster
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="${KUBECONFIG:-/tmp/k0s-admin.conf}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_kubeconfig() {
    if [[ ! -f "$KUBECONFIG" ]]; then
        log_info "Generating kubeconfig from k0s..."
        sudo k0s kubeconfig admin > "$KUBECONFIG"
        chmod 600 "$KUBECONFIG"
    fi
    export KUBECONFIG
}

check_services() {
    log_info "Checking systemd LLM services..."
    local all_running=true

    for svc in llama-server-chat llama-server-embedding llama-server-reranking; do
        if systemctl is-active --quiet "$svc"; then
            log_success "$svc is running"
        else
            log_warn "$svc is not running"
            all_running=false
        fi
    done

    if [[ "$all_running" != "true" ]]; then
        log_warn "Some services are not running. Start them with:"
        echo "  nix run .#generate-configs -- start"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

deploy() {
    check_kubeconfig
    check_services

    log_info "Deploying LLM stack to k0s..."
    kubectl apply -k "$SCRIPT_DIR"

    log_info "Waiting for resources..."
    sleep 3

    log_info "Checking Gateway status..."
    kubectl get gateway -n llm-stack

    log_info "Checking HTTPRoute status..."
    kubectl get httproute -n llm-stack

    log_info "Checking Endpoints..."
    kubectl get endpoints -n llm-stack

    echo ""
    log_success "Deployment complete!"
    echo ""
    echo "LLM API available at: https://llm.stigen.home"
    echo ""
    echo "Test with:"
    echo "  curl -sk https://llm.stigen.home/health"
    echo "  curl -sk https://llm.stigen.home/v1/models"
}

undeploy() {
    check_kubeconfig
    log_info "Removing LLM stack from k0s..."
    kubectl delete -k "$SCRIPT_DIR" --ignore-not-found
    log_success "Undeployed"
}

status() {
    check_kubeconfig

    echo ""
    log_info "=== Kubernetes Resources ==="
    kubectl get all,gateway,httproute -n llm-stack 2>/dev/null || log_warn "Namespace llm-stack not found"

    echo ""
    log_info "=== Systemd Services ==="
    for svc in llama-server-chat llama-server-embedding llama-server-reranking; do
        echo -n "  $svc: "
        if systemctl is-active --quiet "$svc"; then
            echo -e "${GREEN}running${NC}"
        else
            echo -e "${RED}stopped${NC}"
        fi
    done

    echo ""
    log_info "=== Endpoint Connectivity ==="
    for port in 8000 8001 8002; do
        echo -n "  localhost:$port: "
        if curl -s --connect-timeout 2 "http://localhost:$port/health" | grep -q "ok"; then
            echo -e "${GREEN}healthy${NC}"
        else
            echo -e "${RED}unreachable${NC}"
        fi
    done
}

test_gateway() {
    log_info "Testing Cilium Gateway routing..."

    echo ""
    echo -n "  Health check: "
    if curl -sk --connect-timeout 5 "https://llm.stigen.home/health" | grep -q "ok"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
    fi

    echo -n "  Models list: "
    if curl -sk --connect-timeout 5 "https://llm.stigen.home/v1/models" | grep -q "model"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
    fi

    echo ""
    log_info "Full chat test:"
    curl -sk "https://llm.stigen.home/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model": "qwen", "messages": [{"role": "user", "content": "Say hello in 5 words"}], "max_tokens": 50}' \
        --max-time 60 \
        | jq -r '.choices[0].message.content' 2>/dev/null || echo "(Chat service may not be running)"
}

case "${1:-deploy}" in
    deploy|up)
        deploy
        ;;
    undeploy|down|delete)
        undeploy
        ;;
    status)
        status
        ;;
    test)
        test_gateway
        ;;
    *)
        echo "LLM Stack Kubernetes Deployment"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  deploy    Deploy LLM stack to k0s (default)"
        echo "  undeploy  Remove LLM stack from k0s"
        echo "  status    Show deployment and service status"
        echo "  test      Test Gateway API endpoints"
        echo ""
        echo "Prerequisites:"
        echo "  - k0s running with Cilium"
        echo "  - Systemd LLM services installed (nix run .#generate-configs -- install)"
        echo "  - DNS: llm.stigen.home → 192.168.1.31"
        exit 1
        ;;
esac
