#!/usr/bin/env bash
# =============================================================================
# SentinelOps - Alert Receiver (Simple Webhook Logger)
# =============================================================================
# Acts as a minimal HTTP webhook listener for Alertmanager.
# Alertmanager POSTs JSON payloads here; this script logs them to a file.
#
# In production you would replace this with a proper integration:
#   - Slack webhook
#   - PagerDuty / Opsgenie
#   - Email relay
#   - A full notification microservice
#
# This version is for LEARNING purposes only.
#
# Prerequisites:
#   sudo apt-get install netcat-traditional   # (for nc)
#   OR use the Python version below (no extra install needed)
#
# Usage:
#   bash scripts/alert_receiver.sh            # uses Python fallback automatically
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
ALERT_LOG="$LOG_DIR/alerts.log"
PORT=5001

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

mkdir -p "$LOG_DIR"

echo -e "${BOLD}${CYAN}SentinelOps Alert Receiver${NC}"
echo -e "Listening on port ${BOLD}${PORT}${NC}"
echo -e "Alert log: ${BOLD}${ALERT_LOG}${NC}"
echo -e "Press ${BOLD}Ctrl+C${NC} to stop."
echo ""

trap 'echo -e "\n${YELLOW}Alert receiver stopped.${NC}"; exit 0' INT TERM

# ---------------------------------------------------------------------------
# Prefer Python (available on every modern Ubuntu) over netcat
# ---------------------------------------------------------------------------
if command -v python3 &>/dev/null; then
    echo -e "${GREEN}Using Python 3 HTTP server${NC}"
    python3 - <<PYEOF
import http.server
import json
import datetime
import os

PORT    = $PORT
LOGFILE = "$ALERT_LOG"

class AlertHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass   # suppress default access log

    def do_POST(self):
        length  = int(self.headers.get("Content-Length", 0))
        body    = self.rfile.read(length).decode("utf-8")
        ts      = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        # Pretty-print the JSON if possible
        try:
            payload = json.loads(body)
            alerts  = payload.get("alerts", [])
            status  = payload.get("status", "unknown")
            lines   = [f"[{ts}] Alertmanager webhook  status={status}  alerts={len(alerts)}"]
            for a in alerts:
                name  = a.get("labels",      {}).get("alertname", "?")
                sev   = a.get("labels",      {}).get("severity",  "?")
                inst  = a.get("labels",      {}).get("instance",  "?")
                summ  = a.get("annotations", {}).get("summary",   "?")
                lines.append(f"  alert={name}  severity={sev}  instance={inst}")
                lines.append(f"  summary={summ}")
            entry = "\n".join(lines) + "\n" + "-"*60
        except Exception:
            entry = f"[{ts}] Raw payload:\n{body}\n" + "-"*60

        with open(LOGFILE, "a") as fh:
            fh.write(entry + "\n")

        print(f"\033[32m[{ts}]\033[0m Alert received  ({self.path})")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{}')

    # Also accept GET (Alertmanager health checks)
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}')

with http.server.HTTPServer(("0.0.0.0", PORT), AlertHandler) as srv:
    srv.serve_forever()
PYEOF

else
    # Fallback: one-shot netcat loop (requires netcat-traditional)
    echo -e "${YELLOW}Python3 not found - falling back to netcat${NC}"
    if ! command -v nc &>/dev/null; then
        echo -e "${RED}Neither python3 nor nc found.${NC}"
        echo -e "Install one of:"
        echo -e "  sudo apt-get install python3"
        echo -e "  sudo apt-get install netcat-traditional"
        exit 1
    fi

    RESPONSE="HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"

    while true; do
        raw=$(echo -e "$RESPONSE" | nc -l -p "$PORT" -q 1 2>/dev/null || true)
        if [[ -n "$raw" ]]; then
            ts=$(date '+%Y-%m-%d %H:%M:%S')
            {
                echo "[$ts] Alert received via netcat:"
                echo "$raw"
                echo "----"
            } >> "$ALERT_LOG"
            echo -e "${GREEN}[$ts]${NC} Alert logged"
        fi
    done
fi
