#!/usr/bin/env bash
# =============================================================================
# SentinelOps - Continuous System Monitor
# =============================================================================
# A lightweight terminal-based monitor that displays real-time system stats.
# Works WITHOUT Docker/Prometheus — reads directly from the Linux kernel.
# Think of it as a minimal, readable alternative to htop.
#
# Usage:
#   bash scripts/monitor.sh                # Refresh every 5 seconds
#   bash scripts/monitor.sh --interval 2   # Refresh every 2 seconds
#   bash scripts/monitor.sh --once         # Print once and exit
#   bash scripts/monitor.sh --log          # Also write stats to logs/monitor.log
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/monitor.log"

# Thresholds — must match prometheus/rules/alert_rules.yml
CPU_WARN=80;  CPU_CRIT=95
MEM_WARN=85;  MEM_CRIT=95
DISK_WARN=80; DISK_CRIT=90

REFRESH_INTERVAL=5
RUN_ONCE=false
LOG_ENABLED=false

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --interval|-i) REFRESH_INTERVAL="$2"; shift 2 ;;
        --once|-o)     RUN_ONCE=true;         shift ;;
        --log|-l)      LOG_ENABLED=true;      shift ;;
        --help|-h)
            echo "Usage: $0 [--interval N] [--once] [--log]"
            exit 0 ;;
        *) shift ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Pick a color based on value vs warn/crit thresholds
threshold_color() {
    local val="$1" warn="$2" crit="$3"
    local iv="${val%.*}"
    if   (( iv >= crit )); then printf '%s' "$RED"
    elif (( iv >= warn )); then printf '%s' "$YELLOW"
    else                        printf '%s' "$GREEN"
    fi
}

# ASCII progress bar  ████████░░░░  42%
progress_bar() {
    local val="$1" width="${2:-44}" warn="$3" crit="$4"
    local iv="${val%.*}"
    local filled=$(( iv * width / 100 ))
    local empty=$(( width - filled ))
    local col
    col=$(threshold_color "$val" "$warn" "$crit")
    printf "${col}["; printf '%*s' "$filled" | tr ' ' '#'
    printf '%*s' "$empty"  | tr ' ' '-'; printf "]${NC} %d%%" "$iv"
}

# CPU: compare two /proc/stat snapshots 0.5 s apart
get_cpu_pct() {
    local s1 s2 u1 n1 s_1 id1 io1 u2 n2 s_2 id2 io2
    s1=$(grep '^cpu ' /proc/stat)
    sleep 0.5
    s2=$(grep '^cpu ' /proc/stat)
    read -r _ u1 n1 s_1 id1 io1 _ <<< "$s1"
    read -r _ u2 n2 s_2 id2 io2 _ <<< "$s2"
    local tot1=$(( u1+n1+s_1+id1+io1 )) tot2=$(( u2+n2+s_2+id2+io2 ))
    local dtot=$(( tot2-tot1 )) didle=$(( id2-id1 ))
    (( dtot == 0 )) && echo 0 || echo $(( (dtot-didle)*100/dtot ))
}

get_mem_pct()  { awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%.0f",(1-(a/t))*100}' /proc/meminfo; }
get_disk_pct() { df / | awk 'NR==2{gsub(/%/,"",$5); print $5}'; }
get_load()     { read -r l1 l5 l15 _ < /proc/loadavg; echo "$l1 $l5 $l15"; }
get_cores()    { nproc; }

top_procs() {
    ps aux --sort=-%cpu 2>/dev/null \
        | awk 'NR>1 && NR<=6{printf "  %-12s %5s%% %5s%%  %s\n",$1,$3,$4,$11}'
}

# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------
display() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local cpu mem disk
    cpu=$(get_cpu_pct); mem=$(get_mem_pct); disk=$(get_disk_pct)

    local l1 l5 l15; read -r l1 l5 l15 <<< "$(get_load)"
    local cores; cores=$(get_cores)

    local mem_total mem_used mem_avail
    mem_total=$(awk '/^MemTotal:/{printf "%.1f",$2/1024/1024}' /proc/meminfo)
    mem_avail=$(awk '/^MemAvailable:/{printf "%.1f",$2/1024/1024}' /proc/meminfo)
    mem_used=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%.1f",(t-a)/1024/1024}' /proc/meminfo)

    local disk_total disk_used disk_avail
    read -r _ disk_total disk_used disk_avail _ <<< "$(df -h / | awk 'NR==2')"

    clear
    echo -e "${BOLD}${CYAN}"
    echo "  +---------------------------------------------------------+"
    echo "  |       SentinelOps  -  System Monitor                   |"
    echo "  +---------------------------------------------------------+"
    echo -e "${NC}"
    echo -e "  ${CYAN}Timestamp:${NC} $ts   ${CYAN}Cores:${NC} $cores"
    echo ""

    # CPU
    echo -e "  ${BOLD}CPU${NC}"
    echo -n "  "; progress_bar "$cpu" 44 "$CPU_WARN" "$CPU_CRIT"; echo ""
    echo -e "  Load avg: ${CYAN}${l1}${NC} (1m)  ${CYAN}${l5}${NC} (5m)  ${CYAN}${l15}${NC} (15m)"
    echo ""

    # Memory
    echo -e "  ${BOLD}Memory${NC}"
    echo -n "  "; progress_bar "$mem" 44 "$MEM_WARN" "$MEM_CRIT"; echo ""
    echo -e "  ${CYAN}${mem_used} GiB${NC} used  /  ${CYAN}${mem_total} GiB${NC} total  /  ${CYAN}${mem_avail} GiB${NC} available"
    echo ""

    # Disk
    echo -e "  ${BOLD}Disk  (/root)${NC}"
    echo -n "  "; progress_bar "$disk" 44 "$DISK_WARN" "$DISK_CRIT"; echo ""
    echo -e "  ${CYAN}${disk_used}${NC} used  /  ${CYAN}${disk_total}${NC} total  /  ${CYAN}${disk_avail}${NC} free"
    echo ""

    # Top processes
    echo -e "  ${BOLD}Top Processes by CPU${NC}"
    echo -e "  ${BOLD}USER           CPU    MEM   COMMAND${NC}"
    top_procs
    echo ""

    echo -e "  ${CYAN}----------------------------------------------------------${NC}"
    if [[ "$RUN_ONCE" == "false" ]]; then
        echo -e "  Refreshing every ${REFRESH_INTERVAL}s  |  Ctrl+C to exit"
    fi

    # Optionally log
    if [[ "$LOG_ENABLED" == "true" ]]; then
        mkdir -p "$LOG_DIR"
        echo "$ts | CPU:${cpu}% | MEM:${mem}% | DISK:${disk}% | LOAD:${l1}" >> "$LOG_FILE"
    fi
}

trap 'echo -e "\n${YELLOW}Monitor stopped.${NC}"; exit 0' INT TERM

if [[ "$RUN_ONCE" == "true" ]]; then
    display
else
    while true; do
        display
        sleep "$REFRESH_INTERVAL"
    done
fi
