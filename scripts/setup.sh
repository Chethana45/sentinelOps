#!/usr/bin/env bash
# =============================================================================
# SentinelOps - Automated Setup Script
# =============================================================================
# This script validates prerequisites and starts the monitoring stack.
# Run this FIRST when setting up SentinelOps on a new machine.
#
# Usage:
#   bash scripts/setup.sh
#   bash scripts/setup.sh --skip-checks   # Skip prerequisites checks
#   bash scripts/setup.sh --teardown      # Stop and remove all containers
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Flags
SKIP_CHECKS=false
TEARDOWN=false

# ---------------------------------------------------------------------------
# Parse Arguments
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case $arg in
        --skip-checks) SKIP_CHECKS=true ;;
        --teardown)    TEARDOWN=true ;;
        --help)
            echo "Usage: $0 [--skip-checks] [--teardown]"
            echo "  --skip-checks  Skip prerequisite validation"
            echo "  --teardown     Stop and remove all containers and volumes"
            exit 0
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}i  ${NC}$*"; }
success() { echo -e "${GREEN}ok ${NC}$*"; }
warn()    { echo -e "${YELLOW}!! ${NC}$*"; }
error()   { echo -e "${RED}ERR${NC}$*"; }
header()  { echo -e "\n${BOLD}${BLUE}=== $* ===${NC}\n"; }

check_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    if command -v "$cmd" &>/dev/null; then
        success "$cmd is installed: $(${cmd} --version 2>&1 | head -1)"
        return 0
    else
        error "$cmd is NOT installed. $install_hint"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Teardown Mode
# ---------------------------------------------------------------------------
if [[ "$TEARDOWN" == "true" ]]; then
    header "Tearing Down SentinelOps"
    warn "This will STOP all containers and DELETE their data volumes."
    read -rp "Are you sure? (type 'yes' to confirm): " confirm
    if [[ "$confirm" == "yes" ]]; then
        cd "$PROJECT_DIR"
        info "Stopping containers..."
        docker compose down --volumes --remove-orphans
        success "All containers and volumes removed."
    else
        info "Teardown cancelled."
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
clear
echo -e "${BOLD}${CYAN}"
cat << 'EOF'
  ╔═══════════════════════════════════════════════════════╗
  ║         SentinelOps  -  Setup & Deployment            ║
  ║         Server Monitoring & Alerting System           ║
  ╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ---------------------------------------------------------------------------
# Prerequisites Check
# ---------------------------------------------------------------------------
if [[ "$SKIP_CHECKS" == "false" ]]; then
    header "Checking Prerequisites"

    ALL_OK=true

    # Check Docker binary
    if ! check_command "docker" "Install Docker: https://docs.docker.com/engine/install/"; then
        ALL_OK=false
    fi

    # Check Docker daemon is actually running
    if docker info &>/dev/null 2>&1; then
        success "Docker daemon is running"
    else
        error "Docker daemon is NOT running."
        info  "Start it with: sudo service docker start"
        ALL_OK=false
    fi

    # Check Docker Compose V2 (built into Docker CLI)
    if docker compose version &>/dev/null 2>&1; then
        success "Docker Compose V2 is available: $(docker compose version --short)"
    elif command -v docker-compose &>/dev/null; then
        warn "docker-compose (V1) found. V2 is recommended."
        warn "Install V2: https://docs.docker.com/compose/install/"
    else
        error "Docker Compose is NOT installed."
        ALL_OK=false
    fi

    # Check curl (used by health_check.sh)
    check_command "curl" "Install with: sudo apt-get install curl" || true

    if [[ "$ALL_OK" == "false" ]]; then
        echo ""
        error "Prerequisites not met. Fix the errors above and re-run."
        exit 1
    fi

    success "All prerequisites satisfied!"
fi

# ---------------------------------------------------------------------------
# Create Required Directories
# ---------------------------------------------------------------------------
header "Creating Directory Structure"

cd "$PROJECT_DIR"

dirs=(
    "logs"
    "prometheus/rules"
    "prometheus/data"
    "grafana/provisioning/datasources"
    "grafana/provisioning/dashboards"
    "grafana/dashboards"
    "alertmanager/data"
    "scripts"
)

for dir in "${dirs[@]}"; do
    if [[ -d "$dir" ]]; then
        info "Directory exists: $dir"
    else
        mkdir -p "$dir"
        success "Created: $dir"
    fi
done

# ---------------------------------------------------------------------------
# Make Scripts Executable
# ---------------------------------------------------------------------------
header "Setting Script Permissions"

for script in scripts/*.sh; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        success "Made executable: $script"
    fi
done

# ---------------------------------------------------------------------------
# Validate Configuration Files
# ---------------------------------------------------------------------------
header "Validating Configuration Files"

required_files=(
    "docker-compose.yml"
    "prometheus/prometheus.yml"
    "prometheus/rules/alert_rules.yml"
    "alertmanager/alertmanager.yml"
    "grafana/provisioning/datasources/prometheus.yml"
    "grafana/provisioning/dashboards/dashboard.yml"
    "grafana/dashboards/system_overview.json"
)

ALL_PRESENT=true
for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        success "Found: $file"
    else
        error "Missing: $file"
        ALL_PRESENT=false
    fi
done

if [[ "$ALL_PRESENT" == "false" ]]; then
    error "Some config files are missing. Cannot start."
    exit 1
fi

# ---------------------------------------------------------------------------
# Pull Docker Images
# ---------------------------------------------------------------------------
header "Pulling Docker Images"
info "This may take a few minutes on first run (downloads ~1 GB total)..."
docker compose pull
success "All images pulled successfully!"

# ---------------------------------------------------------------------------
# Start Services
# ---------------------------------------------------------------------------
header "Starting SentinelOps Stack"
info "Starting all services in detached mode (-d = runs in background)..."
docker compose up -d
success "Services started!"

# ---------------------------------------------------------------------------
# Wait for Services to be Ready
# ---------------------------------------------------------------------------
header "Waiting for Services to Become Healthy"
info "Services need time to initialise. Waiting up to 120 seconds..."

WAIT_SECONDS=0
MAX_WAIT=120

while [[ $WAIT_SECONDS -lt $MAX_WAIT ]]; do
    running=$(docker compose ps --status running --format "{{.Service}}" 2>/dev/null | wc -l)
    if [[ "$running" -ge 4 ]]; then
        success "All 4 services are running!"
        break
    fi
    printf "  Waiting... %ds / %ds\r" "$WAIT_SECONDS" "$MAX_WAIT"
    sleep 5
    WAIT_SECONDS=$(( WAIT_SECONDS + 5 ))
done

# ---------------------------------------------------------------------------
# Final Status
# ---------------------------------------------------------------------------
header "Deployment Complete!"

echo -e "${GREEN}${BOLD}SentinelOps is running!${NC}"
echo ""
echo -e "${BOLD}Access your monitoring stack:${NC}"
echo -e "  Grafana:       http://localhost:3000"
echo -e "  Username: ${GRAFANA_ADMIN_USER:-admin}   Password: (set in .env)"
echo -e "  Prometheus:    http://localhost:9090"
echo -e "  Alertmanager:  http://localhost:9093"
echo -e "  Node Exporter: http://localhost:9100/metrics"
echo ""
echo -e "${BOLD}Useful next commands:${NC}"
echo -e "  docker compose ps                  # Container status"
echo -e "  docker compose logs -f prometheus  # Follow logs"
echo -e "  bash scripts/health_check.sh       # Run health checks"
echo -e "  bash scripts/monitor.sh            # Terminal system monitor"
echo ""
