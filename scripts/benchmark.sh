#!/usr/bin/env bash
# LLM Server Benchmark Script
# Compares performance across different backends and configurations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
DEFAULT_HOST="localhost"
DEFAULT_PORT="8000"
DEFAULT_MODEL="default"
NUM_REQUESTS="${NUM_REQUESTS:-5}"
PROMPT_TOKENS="${PROMPT_TOKENS:-100}"
MAX_TOKENS="${MAX_TOKENS:-200}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[BENCH]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header() { echo -e "\n${BLUE}=== $* ===${NC}"; }

# Test prompts of varying complexity
PROMPTS=(
    "Write a simple hello world function in Python."
    "Explain the difference between a stack and a queue data structure."
    "Create a bash script that monitors disk usage and sends an alert when usage exceeds 80%."
    "Implement a binary search algorithm in Rust with proper error handling."
    "Design a REST API schema for a todo list application with users, projects, and tasks."
)

# Check if server is responding
check_server() {
    local host="${1:-$DEFAULT_HOST}"
    local port="${2:-$DEFAULT_PORT}"

    if ! curl -s "http://${host}:${port}/health" &>/dev/null; then
        error "Server at ${host}:${port} is not responding"
        return 1
    fi
    return 0
}

# Get server info
get_server_info() {
    local host="${1:-$DEFAULT_HOST}"
    local port="${2:-$DEFAULT_PORT}"

    header "Server Information"

    local props
    props=$(curl -s "http://${host}:${port}/props" 2>/dev/null || echo "{}")

    if [[ "$props" != "{}" ]]; then
        echo "$props" | jq -r '
            "Model: \(.default_generation_settings.model // "unknown")",
            "Context: \(.default_generation_settings.n_ctx // "unknown")",
            "Batch Size: \(.default_generation_settings.n_batch // "unknown")"
        ' 2>/dev/null || echo "Could not parse server properties"
    fi
}

# Single request benchmark
benchmark_single() {
    local host="${1:-$DEFAULT_HOST}"
    local port="${2:-$DEFAULT_PORT}"
    local prompt="$3"
    local max_tokens="${4:-$MAX_TOKENS}"

    local start_time end_time duration
    local response tokens_generated tps

    start_time=$(date +%s.%N)

    response=$(curl -s "http://${host}:${port}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${DEFAULT_MODEL}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}],
            \"max_tokens\": ${max_tokens},
            \"temperature\": 0.7,
            \"stream\": false
        }" 2>/dev/null)

    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)

    # Extract token counts
    tokens_generated=$(echo "$response" | jq -r '.usage.completion_tokens // 0' 2>/dev/null || echo "0")

    if [[ "$tokens_generated" -gt 0 ]]; then
        tps=$(echo "scale=2; $tokens_generated / $duration" | bc)
        echo "$tps"
    else
        echo "0"
    fi
}

# Run full benchmark suite
run_benchmark() {
    local host="${1:-$DEFAULT_HOST}"
    local port="${2:-$DEFAULT_PORT}"
    local label="${3:-default}"

    header "Benchmarking: $label (${host}:${port})"

    if ! check_server "$host" "$port"; then
        return 1
    fi

    get_server_info "$host" "$port"

    local total_tps=0
    local count=0
    local results=()

    log "Running ${NUM_REQUESTS} requests with ${MAX_TOKENS} max tokens each..."
    echo

    for i in $(seq 1 "$NUM_REQUESTS"); do
        local prompt="${PROMPTS[$((i % ${#PROMPTS[@]}))]}"
        local tps

        printf "  Request %d/%d: " "$i" "$NUM_REQUESTS"
        tps=$(benchmark_single "$host" "$port" "$prompt" "$MAX_TOKENS")

        if [[ "$tps" != "0" ]]; then
            printf "${GREEN}%.2f tok/s${NC}\n" "$tps"
            total_tps=$(echo "$total_tps + $tps" | bc)
            results+=("$tps")
            ((count++))
        else
            printf "${RED}failed${NC}\n"
        fi
    done

    echo

    if [[ $count -gt 0 ]]; then
        local avg_tps
        avg_tps=$(echo "scale=2; $total_tps / $count" | bc)

        # Calculate min/max
        local min_tps max_tps
        min_tps=$(printf '%s\n' "${results[@]}" | sort -n | head -1)
        max_tps=$(printf '%s\n' "${results[@]}" | sort -n | tail -1)

        echo -e "${CYAN}Results for $label:${NC}"
        echo "  Average: ${GREEN}${avg_tps} tok/s${NC}"
        echo "  Min: ${min_tps} tok/s"
        echo "  Max: ${max_tps} tok/s"
        echo "  Successful: ${count}/${NUM_REQUESTS}"

        # Return average for comparison
        echo "$avg_tps"
    else
        warn "No successful requests"
        echo "0"
    fi
}

# Compare multiple servers
compare_servers() {
    header "Server Comparison Benchmark"

    local servers=("$@")
    local results=()

    for server in "${servers[@]}"; do
        local host port label
        IFS=':' read -r host port label <<< "$server"
        port="${port:-8000}"
        label="${label:-$host:$port}"

        if check_server "$host" "$port" 2>/dev/null; then
            local result
            result=$(run_benchmark "$host" "$port" "$label" | tail -1)
            results+=("$label:$result")
        else
            warn "Skipping $label - server not responding"
        fi
    done

    if [[ ${#results[@]} -gt 1 ]]; then
        header "Comparison Summary"

        printf "%-30s %15s\n" "Server" "Avg tok/s"
        printf "%-30s %15s\n" "------" "---------"

        for result in "${results[@]}"; do
            IFS=':' read -r label tps <<< "$result"
            printf "%-30s %15s\n" "$label" "$tps"
        done
    fi
}

# Stress test
stress_test() {
    local host="${1:-$DEFAULT_HOST}"
    local port="${2:-$DEFAULT_PORT}"
    local concurrent="${3:-4}"
    local duration="${4:-60}"

    header "Stress Test: ${concurrent} concurrent for ${duration}s"

    if ! check_server "$host" "$port"; then
        return 1
    fi

    log "Starting stress test..."

    local pids=()
    local results_file=$(mktemp)

    # Launch concurrent workers
    for i in $(seq 1 "$concurrent"); do
        (
            local count=0
            local end_time=$(($(date +%s) + duration))

            while [[ $(date +%s) -lt $end_time ]]; do
                local prompt="${PROMPTS[$((RANDOM % ${#PROMPTS[@]}))]}"
                if benchmark_single "$host" "$port" "$prompt" 50 > /dev/null 2>&1; then
                    ((count++))
                fi
            done

            echo "$count" >> "$results_file"
        ) &
        pids+=($!)
    done

    # Wait for workers
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Sum results
    local total=0
    while read -r count; do
        total=$((total + count))
    done < "$results_file"
    rm -f "$results_file"

    local rps
    rps=$(echo "scale=2; $total / $duration" | bc)

    echo
    log "Stress test complete"
    echo "  Total requests: $total"
    echo "  Duration: ${duration}s"
    echo "  Throughput: ${GREEN}${rps} req/s${NC}"
}

# Context length test
test_context_lengths() {
    local host="${1:-$DEFAULT_HOST}"
    local port="${2:-$DEFAULT_PORT}"

    header "Context Length Performance Test"

    if ! check_server "$host" "$port"; then
        return 1
    fi

    local contexts=(1024 4096 8192 16384 32768 65536)

    for ctx in "${contexts[@]}"; do
        # Generate prompt of appropriate length
        local prompt=""
        local words=$((ctx / 4))  # Rough estimate: 4 chars per token

        for _ in $(seq 1 $words); do
            prompt+="word "
        done

        printf "  Context %6d: " "$ctx"

        local start_time end_time
        start_time=$(date +%s.%N)

        # Just measure time to first token
        local response
        response=$(curl -s --max-time 120 "http://${host}:${port}/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"${DEFAULT_MODEL}\",
                \"messages\": [{\"role\": \"user\", \"content\": \"${prompt:0:$((ctx*4))}\"}],
                \"max_tokens\": 10,
                \"stream\": false
            }" 2>/dev/null || echo "{}")

        end_time=$(date +%s.%N)

        if echo "$response" | jq -e '.choices[0]' &>/dev/null; then
            local duration
            duration=$(echo "$end_time - $start_time" | bc)
            printf "${GREEN}%.2fs${NC}\n" "$duration"
        else
            printf "${RED}failed/timeout${NC}\n"
        fi
    done
}

# Usage
usage() {
    cat << EOF
Usage: $0 [command] [options]

Commands:
    single [host:port]              Run single server benchmark
    compare <server1> <server2>...  Compare multiple servers
    stress [host:port] [conc] [dur] Stress test with concurrent requests
    context [host:port]             Test various context lengths

Options:
    -n, --requests NUM     Number of requests (default: 5)
    -t, --tokens NUM       Max tokens per request (default: 200)
    -h, --help             Show this help

Examples:
    $0 single localhost:8000
    $0 compare localhost:8000:UMA localhost:8001:Vulkan
    $0 stress localhost:8000 8 120
    $0 context localhost:8000

Environment:
    NUM_REQUESTS    Override default request count
    MAX_TOKENS      Override default max tokens
EOF
}

main() {
    case "${1:-}" in
        single)
            shift
            local server="${1:-localhost:8000}"
            IFS=':' read -r host port <<< "$server"
            run_benchmark "${host:-localhost}" "${port:-8000}" "$server"
            ;;
        compare)
            shift
            if [[ $# -lt 2 ]]; then
                error "Need at least 2 servers to compare"
                exit 1
            fi
            compare_servers "$@"
            ;;
        stress)
            shift
            local server="${1:-localhost:8000}"
            local concurrent="${2:-4}"
            local duration="${3:-60}"
            IFS=':' read -r host port <<< "$server"
            stress_test "${host:-localhost}" "${port:-8000}" "$concurrent" "$duration"
            ;;
        context)
            shift
            local server="${1:-localhost:8000}"
            IFS=':' read -r host port <<< "$server"
            test_context_lengths "${host:-localhost}" "${port:-8000}"
            ;;
        -h|--help|help)
            usage
            ;;
        "")
            # Default: run single benchmark on localhost:8000
            run_benchmark "localhost" "8000" "default"
            ;;
        *)
            error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
