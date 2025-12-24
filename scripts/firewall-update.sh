#!/usr/bin/env bash
# Firewall rule update script for local-llama infrastructure
# Opens ports for LLM services and allows network access
#
# Usage:
#   ./scripts/firewall-update.sh [enable|disable|status]
#
# Ports:
#   4000  - LiteLLM Proxy (main API gateway)
#   8000  - Chat model (Qwen3-Coder)
#   8001  - Embeddings model (Qwen3-Embed)
#   8002  - Reranker model (BGE-Reranker)

set -euo pipefail

# Configuration
LITELLM_PORT="${LITELLM_PORT:-4000}"
CHAT_PORT="${CHAT_PORT:-8000}"
EMBED_PORT="${EMBED_PORT:-8001}"
RERANK_PORT="${RERANK_PORT:-8002}"

# All ports to manage
PORTS=("$LITELLM_PORT" "$CHAT_PORT" "$EMBED_PORT" "$RERANK_PORT")

# Service names for comments/labels
declare -A PORT_NAMES=(
    ["$LITELLM_PORT"]="LiteLLM-Proxy"
    ["$CHAT_PORT"]="LLaMA-Chat"
    ["$EMBED_PORT"]="LLaMA-Embed"
    ["$RERANK_PORT"]="LLaMA-Rerank"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect which firewall is active
detect_firewall() {
    if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
        echo "ufw"
    elif command -v firewall-cmd &>/dev/null && sudo systemctl is-active firewalld &>/dev/null; then
        echo "firewalld"
    elif command -v iptables &>/dev/null; then
        echo "iptables"
    else
        echo "none"
    fi
}

# UFW functions
ufw_enable_ports() {
    log_info "Configuring UFW firewall rules..."

    for port in "${PORTS[@]}"; do
        local name="${PORT_NAMES[$port]}"
        if sudo ufw status | grep -q "$port/tcp.*ALLOW"; then
            log_success "Port $port ($name) already allowed"
        else
            sudo ufw allow "$port/tcp" comment "$name"
            log_success "Opened port $port ($name)"
        fi
    done

    # Reload to ensure rules are active
    sudo ufw reload
}

ufw_disable_ports() {
    log_info "Removing UFW firewall rules..."

    for port in "${PORTS[@]}"; do
        local name="${PORT_NAMES[$port]}"
        if sudo ufw status | grep -q "$port/tcp"; then
            sudo ufw delete allow "$port/tcp"
            log_success "Closed port $port ($name)"
        else
            log_warn "Port $port ($name) was not open"
        fi
    done
}

ufw_status() {
    echo ""
    log_info "UFW Firewall Status:"
    echo ""
    sudo ufw status verbose | head -20
    echo ""
    log_info "LLM Service Ports:"
    for port in "${PORTS[@]}"; do
        local name="${PORT_NAMES[$port]}"
        if sudo ufw status | grep -q "$port/tcp.*ALLOW"; then
            echo -e "  ${GREEN}[OPEN]${NC}   $port/tcp - $name"
        else
            echo -e "  ${RED}[CLOSED]${NC} $port/tcp - $name"
        fi
    done
}

# Firewalld functions
firewalld_enable_ports() {
    log_info "Configuring firewalld rules..."

    for port in "${PORTS[@]}"; do
        local name="${PORT_NAMES[$port]}"
        sudo firewall-cmd --permanent --add-port="$port/tcp"
        log_success "Opened port $port ($name)"
    done

    sudo firewall-cmd --reload
}

firewalld_disable_ports() {
    log_info "Removing firewalld rules..."

    for port in "${PORTS[@]}"; do
        local name="${PORT_NAMES[$port]}"
        sudo firewall-cmd --permanent --remove-port="$port/tcp" 2>/dev/null || true
        log_success "Closed port $port ($name)"
    done

    sudo firewall-cmd --reload
}

firewalld_status() {
    echo ""
    log_info "Firewalld Status:"
    echo ""
    sudo firewall-cmd --list-all
    echo ""
    log_info "LLM Service Ports:"
    for port in "${PORTS[@]}"; do
        local name="${PORT_NAMES[$port]}"
        if sudo firewall-cmd --list-ports | grep -q "$port/tcp"; then
            echo -e "  ${GREEN}[OPEN]${NC}   $port/tcp - $name"
        else
            echo -e "  ${RED}[CLOSED]${NC} $port/tcp - $name"
        fi
    done
}

# iptables functions (fallback)
iptables_enable_ports() {
    log_info "Configuring iptables rules..."

    for port in "${PORTS[@]}"; do
        local name="${PORT_NAMES[$port]}"
        # Check if rule already exists
        if sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            log_success "Port $port ($name) already allowed"
        else
            sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT -m comment --comment "$name"
            log_success "Opened port $port ($name)"
        fi
    done

    # Save rules (works on Debian/Ubuntu)
    if command -v iptables-save &>/dev/null; then
        log_info "Saving iptables rules..."
        sudo sh -c 'iptables-save > /etc/iptables/rules.v4' 2>/dev/null || \
            sudo sh -c 'iptables-save > /etc/iptables.rules' 2>/dev/null || \
            log_warn "Could not persist iptables rules. They will be lost on reboot."
    fi
}

iptables_disable_ports() {
    log_info "Removing iptables rules..."

    for port in "${PORTS[@]}"; do
        local name="${PORT_NAMES[$port]}"
        sudo iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null && \
            log_success "Closed port $port ($name)" || \
            log_warn "Port $port ($name) was not open"
    done
}

iptables_status() {
    echo ""
    log_info "iptables INPUT Chain:"
    echo ""
    sudo iptables -L INPUT -n --line-numbers | head -20
    echo ""
    log_info "LLM Service Ports:"
    for port in "${PORTS[@]}"; do
        local name="${PORT_NAMES[$port]}"
        if sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            echo -e "  ${GREEN}[OPEN]${NC}   $port/tcp - $name"
        else
            echo -e "  ${RED}[CLOSED]${NC} $port/tcp - $name"
        fi
    done
}

# Main logic
main() {
    local action="${1:-status}"
    local firewall

    firewall=$(detect_firewall)

    if [[ "$firewall" == "none" ]]; then
        log_warn "No active firewall detected. Ports should be accessible."
        exit 0
    fi

    log_info "Detected firewall: $firewall"

    case "$action" in
        enable|open|allow)
            case "$firewall" in
                ufw) ufw_enable_ports ;;
                firewalld) firewalld_enable_ports ;;
                iptables) iptables_enable_ports ;;
            esac
            echo ""
            log_success "Firewall rules updated. LLM services accessible from network."
            ;;

        disable|close|deny)
            case "$firewall" in
                ufw) ufw_disable_ports ;;
                firewalld) firewalld_disable_ports ;;
                iptables) iptables_disable_ports ;;
            esac
            echo ""
            log_success "Firewall rules removed. LLM services only accessible locally."
            ;;

        status|show)
            case "$firewall" in
                ufw) ufw_status ;;
                firewalld) firewalld_status ;;
                iptables) iptables_status ;;
            esac
            ;;

        *)
            echo "Usage: $0 [enable|disable|status]"
            echo ""
            echo "Commands:"
            echo "  enable   Open ports for LLM services (allows network access)"
            echo "  disable  Close ports for LLM services (localhost only)"
            echo "  status   Show current firewall rules for LLM ports"
            echo ""
            echo "Ports managed:"
            for port in "${PORTS[@]}"; do
                echo "  $port - ${PORT_NAMES[$port]}"
            done
            exit 1
            ;;
    esac
}

main "$@"
