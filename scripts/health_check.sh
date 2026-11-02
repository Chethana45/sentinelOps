#!/usr/bin/env bash
# =============================================================================
# SentinelOps - Service Health Check Script
# =============================================================================
# Checks the health of all services in the monitoring stack.
# Run from the sentinelOps project directory.
#
# Usage:
#   bash scripts/health_check.sh
#   bash scripts/health_check.sh --verbose
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/health_check.log"

# Service endpoints
PROMETHEUS_URL="http://localhost:9090"
GRAFANA_URL="http://localhost:3000"
ALERTMANAGER_URL="http://localhost:9093"
NODE_EXPORTER_URL="http://localhost:9100"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

VERBOSE=false
for arg in "$@"; do
    case $arg in
        --verbose|-v) VERBOSE=true ;;
        --help|-h)
            echo "Usage: $0 [--verbose]"
            exit 0
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}================================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}================================================${NC}"
}

print_status() {
    local service="$1" status="$2" detail="${3:-}"
    if   [[ "$status" == "OK"      ]]; then echo -e "  ${GREEN}ok${NC}  ${BOLD}${service}${NC}: ${GREEN}${status}${NC} ${detail}"
    elif [[ "$status" == "WARNING" ]]; then echo -e "  ${YELLOW}!!${NC}  ${BOLD}${service}${NC}: ${YELLOW}${status}${NC} ${detail}"
    else                                    echo -e "  ${RED}ERR${NC} ${BOLD}${service}${NC}: ${RED}${status}${NC} ${detail}"
    fi
}

log() {
    mkdir -p "$LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

check_http() {
    local url="$1" path="${2:-}"
    curl -sf --max-time 5 --output /dev/null "${url}${path}" 2>/dev/null
}

check_container() {
    docker ps --filter "name=$1" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q "$1"
}

get_container_health() {
    docker inspect --format='{{.State.Health.Status}}' "$1" 2>/dev/null || echo "unknown"
}

# ---------------------------------------------------------------------------
# Per-service check
# ---------------------------------------------------------------------------
check_service() {
    local name="$1" container="$2" url="$3" health_path="${4:-}"
    TOTAL=$(( TOTAL + 1 ))

    if ! check_container "$container"; then
        FAILED=$(( FAILED + 1 ))
        print_status "$name" "FAIL" "(container not running)"
        log "FAIL: $name - container not running"
        return
    fi

    if ! check_http "$url" "$health_path"; then
        WARNINGS=$(( WARNINGS + 1 ))
        print_status "$name" "WARNING" "(container up but HTTP not responding)"
        log "WARNING: $name - HTTP not responding"
        return
    fi

    local health
    health=$(get_container_health "$container")
    case "$health" in
        healthy|unknown)
            PASSED=$(( PASSED + 1 ))
            print_status "$name" "OK" "(docker health: $health)"
            log "OK: $name"
            ;;
        starting)
            WARNINGS=$(( WARNINGS + 1 ))
            print_status "$name" "WARNING" "(still starting)"
            log "WARNING: $name - still starting"
            ;;
        *)
            WARNINGS=$(( WARNINGS + 1 ))
            print_status "$name" "WARNING" "(docker health: $health)"
            log "WARNING: $name - health=$health"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
clear
echo ""
echo -e "${BOLD}${CYAN}  SentinelOps - Health Check${NC}"
echo -e "  $(date '+%A, %d %B %Y  %H:%M:%S')"

print_header "Service Health"
check_service "Prometheus"    "sentinelops-prometheus"    "$PROMETHEUS_URL"    "/-/healthy"
check_service "Node Exporter" "sentinelops-node-exporter" "$NODE_EXPORTER_URL" "/metrics"
check_service "Grafana"       "sentinelops-grafana"       "$GRAFANA_URL"       "/api/health"
check_service "Alertmanager"  "sentinelops-alertmanager"  "$ALERTMANAGER_URL"  "/-/healthy"

# ---------------------------------------------------------------------------
# Prometheus scrape target status
# ---------------------------------------------------------------------------
print_header "Prometheus Scrape Targets"

if check_http "$PROMETHEUS_URL" "/-/ready"; then
    targets_json=$(curl -sf --max-time 5 "$PROMETHEUS_URL/api/v1/targets" 2>/dev/null || echo "")
    if [[ -n "$targets_json" ]]; then
        up_count=$(echo "$targets_json"   | grep -o '"health":"up"'   | wc -l)
        down_count=$(echo "$targets_json" | grep -o '"health":"down"' | wc -l)
        echo -e "  ${GREEN}ok${NC}  Targets UP:   ${GREEN}${up_count}${NC}"
        if [[ "$down_count" -gt 0 ]]; then
            echo -e "  ${RED}ERR${NC} Targets DOWN: ${RED}${down_count}${NC}"
        else
            echo -e "  ${GREEN}ok${NC}  Targets DOWN: ${GREEN}0${NC}"
        fi
    else
        echo -e "  ${YELLOW}!!${NC}  Could not query Prometheus API"
    fi
else
    echo -e "  ${RED}ERR${NC} Prometheus not ready - skipping target check"
fi

# ---------------------------------------------------------------------------
# Host system snapshot
# ---------------------------------------------------------------------------
print_header "Host System Resources"

cpu_idle=$(grep '^cpu ' /proc/stat | awk '{idle=$5; total=0; for(i=2;i<=NF;i++) total+=$i; printf "%.0f", (1-(idle/total))*100}')
echo -e "  ${CYAN}CPU Usage:${NC}  ${cpu_idle}%"

mem_info=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%.1f GiB used / %.1f GiB total", (t-a)/1024/1024, t/1024/1024}' /proc/meminfo)
echo -e "  ${CYAN}Memory:${NC}     ${mem_info}"

disk_info=$(df -h / | awk 'NR==2{print $3 " used / " $2 " total (" $5 " full)"}')
echo -e "  ${CYAN}Disk (/):${NC}   ${disk_info}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_header "Summary"
echo -e "  Total:    ${BOLD}${TOTAL}${NC}"
echo -e "  Passed:   ${GREEN}${PASSED}${NC}"
echo -e "  Warnings: ${YELLOW}${WARNINGS}${NC}"
echo -e "  Failed:   ${RED}${FAILED}${NC}"
echo ""

if [[ "$FAILED" -gt 0 ]]; then
    echo -e "  ${RED}${BOLD}UNHEALTHY - $FAILED service(s) are down!${NC}"
    echo -e "  Run: docker compose ps"
    echo -e "  Run: docker compose logs <service>"
    exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
    echo -e "  ${YELLOW}${BOLD}DEGRADED - $WARNINGS service(s) have warnings${NC}"
    exit 0
else
    echo -e "  ${GREEN}${BOLD}HEALTHY - All services are running!${NC}"
    echo ""
    echo -e "  Grafana:       http://localhost:3000  (credentials from your .env file)"
    echo -e "  Prometheus:    http://localhost:9090"
    echo -e "  Alertmanager:  http://localhost:9093"
    echo -e "  Node Exporter: http://localhost:9100/metrics"
    exit 0
fi
