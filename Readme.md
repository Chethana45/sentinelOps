# 🛡️ SentinelOps — Server Monitoring & Alerting System

> A complete, beginner-friendly, production-ready monitoring stack built with Prometheus, Grafana, Node Exporter, and Alertmanager — all running in Docker on Ubuntu / WSL2.

[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://www.docker.com/)
[![Prometheus](https://img.shields.io/badge/Prometheus-v2.51-E6522C?logo=prometheus)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Grafana-v10.3-F46800?logo=grafana)](https://grafana.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 📋 Table of Contents

- [What Is This?](#-what-is-this)
- [Architecture](#-architecture)
- [Project Structure](#-project-structure)
- [Tech Stack](#-tech-stack)
- [Prerequisites](#-prerequisites)
- [Environment Setup](#-environment-setup)
- [Quick Start](#-quick-start)
- [Accessing Services](#-accessing-services)
- [Dashboard Panels](#-dashboard-panels)
- [Alert Rules](#-alert-rules)
- [Bash Scripts](#-bash-scripts)
- [Common Commands](#-common-commands)
- [Troubleshooting](#-troubleshooting)
- [Security Practices](#-security-practices)
- [Screenshots Checklist](#-screenshots-checklist)
- [Next Steps](#-next-steps)

---

## 🤔 What Is This?

SentinelOps answers the question every operations team asks:

> *"Is my server healthy right now — and will it stay that way?"*

It automatically:
- **Collects** CPU, memory, disk, and network metrics every 15 seconds
- **Stores** that data for 15 days so you can spot trends
- **Visualizes** everything in live Grafana dashboards
- **Alerts** you when something goes wrong (CPU > 80%, disk > 90%, service down)

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                  Host (Ubuntu / WSL2 on Windows)                 │
│                                                                  │
│  ┌────────────────── Docker network: monitoring ───────────────┐ │
│  │                                                              │ │
│  │  ┌─────────────┐  scrapes    ┌────────────────────────┐    │ │
│  │  │             │ ──────────► │    Node Exporter        │    │ │
│  │  │  Prometheus │  every 15s  │    :9100                │    │ │
│  │  │  :9090      │             │  reads /proc /sys /     │    │ │
│  │  │             │ ◄── queries ─────────────────────────┐│    │ │
│  │  │             │                                      ││    │ │
│  │  │             │ ─ fires alerts ─► ┌──────────────┐  ││    │ │
│  │  └─────────────┘                   │ Alertmanager │  ││    │ │
│  │         ▲                          │ :9093        │  ││    │ │
│  │         │ queries                  └──────────────┘  ││    │ │
│  │  ┌─────────────┐                                     ││    │ │
│  │  │   Grafana   │─────────────────────────────────────┘│    │ │
│  │  │   :3000     │                                       │    │ │
│  │  └─────────────┘                                       │    │ │
│  └────────────────────────────────────────────────────────┘    │ │
│                                                                  │
│  Ports forwarded to Windows browser:                             │
│  :3000 (Grafana)  :9090 (Prometheus)  :9093 (Alertmanager)      │
│  :9100 (Node Exporter raw metrics)                               │
└──────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Node Exporter** reads raw kernel data (`/proc`, `/sys`) and exposes metrics
2. **Prometheus** scrapes Node Exporter every 15 s and stores in its time-series DB
3. **Grafana** queries Prometheus via PromQL and renders live dashboards
4. **Alertmanager** receives fired alerts from Prometheus and routes notifications

---

## 📁 Project Structure

```
sentinelOps/
├── .env                           # Your local secrets (gitignored — never commit)
├── .env.example                   # Template — safe to commit, no real secrets
├── .gitignore                     # Protects .env, logs, runtime data
├── docker-compose.yml             # All 4 services — reads variables from .env
├── Makefile                       # Shortcut commands (make up, make health, etc.)
├── README.md                      # This file
│
├── prometheus/
│   ├── prometheus.yml             # Scrape targets, Alertmanager endpoint
│   ├── rules/
│   │   └── alert_rules.yml        # 12 alert rules (CPU, RAM, disk, network)
│   └── data/                      # TSDB storage — gitignored, Docker-managed
│
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── prometheus.yml     # Auto-connects Grafana → Prometheus on startup
│   │   └── dashboards/
│   │       └── dashboard.yml      # Tells Grafana where to find dashboard JSON
│   ├── dashboards/
│   │   └── system_overview.json   # 24-panel system monitoring dashboard
│   └── data/                      # Grafana DB — gitignored, Docker-managed
│
├── alertmanager/
│   ├── alertmanager.yml           # Routing tree, inhibitions, receivers
│   └── data/                      # Alert state — gitignored, Docker-managed
│
├── scripts/
│   ├── setup.sh                   # Automated prerequisite check and deploy
│   ├── health_check.sh            # Verify all 4 services are healthy
│   ├── monitor.sh                 # Real-time terminal system monitor
│   ├── alert_receiver.sh          # Simple webhook listener for Alertmanager
│   ├── check_targets.py           # Python: query Prometheus targets API
│   ├── check_grafana.py           # Python: verify Grafana dashboards via API
│   ├── validate_queries.py        # Python: validate all 27 dashboard PromQL queries
│   └── deploy_dashboard.py        # Python: push dashboard JSON to Grafana API
│
└── logs/                          # Script output — gitignored
```

---

## 🛠️ Tech Stack

| Tool | Version | Role |
|------|---------|------|
| **Docker** | 24+ | Container runtime |
| **Docker Compose** | V2 | Multi-service orchestration |
| **Prometheus** | 2.51 | Metrics collection and storage |
| **Node Exporter** | 1.7 | Linux hardware/OS metrics exporter |
| **Grafana** | 10.3 | Visualization and dashboards |
| **Alertmanager** | 0.27 | Alert routing and notifications |
| **Bash** | 5+ | Automation scripts |

---

## ✅ Prerequisites

### Check if Docker is installed

```bash
docker --version
docker compose version
```

### Install Docker in WSL2 (if not present)

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker
```

### Start Docker daemon

```bash
sudo service docker start
docker info   # should show server info without errors
```

---

## 🔐 Environment Setup

> **Security rule:** Real credentials go in `.env` (gitignored). Only `.env.example` is committed.

### Step 1 — Copy the template

```bash
cd ~/path/to/sentinelOps
cp .env.example .env
```

### Step 2 — Edit your local `.env`

Open `.env` in any editor and set values:

```bash
nano .env
```

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_ADMIN_USER` | `admin` | Grafana login username |
| `GRAFANA_ADMIN_PASSWORD` | *(must set)* | Grafana login password |
| `GRAFANA_PORT` | `3000` | Host port for Grafana |
| `PROMETHEUS_PORT` | `9090` | Host port for Prometheus |
| `ALERTMANAGER_PORT` | `9093` | Host port for Alertmanager |
| `NODE_EXPORTER_PORT` | `9100` | Host port for Node Exporter |
| `PROMETHEUS_RETENTION_TIME` | `15d` | How long metrics are kept |
| `SMTP_HOST` | *(blank)* | Optional: SMTP server for email alerts |
| `SMTP_PASSWORD` | *(blank)* | Optional: SMTP password |
| `SLACK_WEBHOOK_URL` | *(blank)* | Optional: Slack webhook for alerts |

> **Important:** If `SMTP_*` variables are left empty, email alerting is simply disabled. The stack starts correctly either way.

### Step 3 — Verify `.env` is gitignored

```bash
git check-ignore -v .env          # should print: .gitignore:6:.env
git check-ignore -v .env.example  # should print nothing (not ignored — correct)
```

---

## 🚀 Quick Start

```bash
# 1. Navigate to project
cd /mnt/c/Users/yourname/sentinelOps   # WSL2 path to Windows Desktop

# 2. Copy and configure environment
cp .env.example .env
nano .env   # set GRAFANA_ADMIN_PASSWORD at minimum

# 3. Make scripts executable
chmod +x scripts/*.sh

# 4. Start the stack
docker compose up -d

# 5. Verify all containers are healthy
docker compose ps
bash scripts/health_check.sh
```

---

## 🌐 Accessing Services

Once running, open these in your **Windows browser** (WSL2 ports forward automatically):

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** | http://localhost:3000 | `admin` / *(your .env password)* |
| **Prometheus** | http://localhost:9090 | None required |
| **Alertmanager** | http://localhost:9093 | None required |
| **Node Exporter** | http://localhost:9100/metrics | None required |

### Key Prometheus pages

| Page | URL | What to check |
|------|-----|---------------|
| Targets | http://localhost:9090/targets | All 4 should be green (UP) |
| Alerts | http://localhost:9090/alerts | Active alert rules |
| Graph | http://localhost:9090/graph | Run PromQL queries manually |
| Config | http://localhost:9090/config | Active Prometheus configuration |
| Rules  | http://localhost:9090/rules  | All 12 loaded alert rules |

---

## 📊 Dashboard Panels

Navigate to: **Grafana → Dashboards → SentinelOps → SentinelOps - System Overview**

Or directly: `http://localhost:3000/d/sentinelops-system-overview`

| Section | Panels | PromQL Used |
|---------|--------|-------------|
| **Service Availability** | Node Exporter UP/DOWN, Prometheus UP/DOWN, Alertmanager UP/DOWN, Grafana UP/DOWN, System Uptime, CPU Cores | `up{job="..."}`, `node_time_seconds - node_boot_time_seconds` |
| **CPU** | Usage % gauge, Time series (total/user/system/iowait/load1/load5) | `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| **Memory** | RAM % gauge, Available stat, Time series (used/cache/available/swap) | `(1 - node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)*100` |
| **Disk** | Usage % gauge, Free space stat, I/O read/write graph | `node_filesystem_free_bytes{mountpoint="/"}` |
| **Network** | Per-interface receive/transmit, Packet rate | `rate(node_network_receive_bytes_total[5m])` |
| **System Load** | Load avg vs CPU cores, Processes + file descriptors | `node_load1`, `node_procs_running` |

### Color thresholds

| Metric | Yellow | Orange | Red |
|--------|--------|--------|-----|
| CPU | 60% | 80% | 90% |
| Memory | 60% | 80% | 90% |
| Disk | 70% | 80% | 90% |

---

## 🚨 Alert Rules (12 rules)

Located in [`prometheus/rules/alert_rules.yml`](prometheus/rules/alert_rules.yml)

| Alert | Condition | Duration | Severity |
|-------|-----------|----------|----------|
| `InstanceDown` | `up == 0` | 1m | critical |
| `NodeExporterDown` | absent(node-exporter) | 1m | critical |
| `HighCpuUsage` | CPU > 80% | 5m | warning |
| `CriticalCpuUsage` | CPU > 95% | 2m | critical |
| `HighMemoryUsage` | RAM > 85% | 5m | warning |
| `CriticalMemoryUsage` | RAM > 95% | 2m | critical |
| `SwapUsageHigh` | Swap > 80% | 5m | warning |
| `LowDiskSpace` | Disk > 80% | 5m | warning |
| `CriticalDiskSpace` | Disk > 90% | 2m | critical |
| `DiskWillFillIn24Hours` | linear_predict fill < 24h | 30m | warning |
| `HighNetworkReceive` | Receive > 100 MB/s | 5m | warning |
| `HighSystemLoad` | load15 > 1.5× cores | 10m | warning |

---

## 📜 Bash Scripts

```bash
# Full setup (validates prerequisites, starts stack)
bash scripts/setup.sh

# Check all 4 services are healthy
bash scripts/health_check.sh

# Real-time terminal system monitor
bash scripts/monitor.sh                # refresh every 5s
bash scripts/monitor.sh --interval 2  # refresh every 2s
bash scripts/monitor.sh --once        # print once and exit

# Start the webhook alert receiver (logs alerts to logs/alerts.log)
bash scripts/alert_receiver.sh
```

### Python diagnostic scripts

```bash
# Check Prometheus targets and live metric samples
python3 scripts/check_targets.py

# Check Grafana datasources and dashboards via API
python3 scripts/check_grafana.py

# Validate all 27 dashboard PromQL queries return real data
python3 scripts/validate_queries.py

# Push dashboard JSON to Grafana (idempotent — safe to re-run)
python3 scripts/deploy_dashboard.py
```

---

## 📌 Common Commands

```bash
# Start / Stop / Restart
docker compose up -d
docker compose down
docker compose restart

# Status
docker compose ps
docker stats --no-stream

# Logs
docker compose logs -f
docker compose logs -f prometheus
docker compose logs -f grafana
docker compose logs --tail=100 alertmanager

# Config validation (run before restarting!)
docker compose config --quiet
docker exec sentinelops-prometheus promtool check config /etc/prometheus/prometheus.yml
docker exec sentinelops-prometheus promtool check rules /etc/prometheus/rules/alert_rules.yml

# Hot-reload Prometheus config (no container restart needed)
curl -X POST http://localhost:9090/-/reload

# Open a shell in a container
docker exec -it sentinelops-prometheus sh
docker exec -it sentinelops-grafana bash

# Makefile shortcuts
make up
make down
make ps
make logs
make health
make monitor
make reload-prometheus
make validate
```

---

## 🔧 Troubleshooting

### Docker daemon not running
```bash
sudo service docker start
docker info
```

### Port already in use
```bash
sudo lsof -i :3000          # find what's using port 3000
sudo kill -9 <PID>
# OR change the port in .env: GRAFANA_PORT=3001
```

### Grafana shows "No data" on panels
```bash
# 1. Confirm Prometheus is healthy
curl http://localhost:9090/-/healthy

# 2. Confirm targets are up
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep health

# 3. Test a query manually in browser
# http://localhost:9090/graph  →  query: up

# 4. Verify datasource in Grafana
# Connections → Data sources → Prometheus → Save & Test
```

### GRAFANA_ADMIN_PASSWORD error on startup
```bash
# docker compose will refuse to start if this is unset
# Make sure .env exists and contains GRAFANA_ADMIN_PASSWORD=something
cat .env | grep GRAFANA
```

### Dashboard not loading after container restart
```bash
# Provisioning should load it automatically. Check Grafana logs:
docker compose logs grafana | grep -i provision

# If dashboard is missing, re-push it:
python3 scripts/deploy_dashboard.py
```

### Prometheus config error
```bash
# Validate BEFORE reloading
docker exec sentinelops-prometheus promtool check config /etc/prometheus/prometheus.yml
# If valid, reload without restart:
curl -X POST http://localhost:9090/-/reload
```

### Full reset (last resort — deletes all metric history)
```bash
docker compose down --volumes --remove-orphans
docker compose up -d
```

---

## 🔒 Security Practices

| Practice | Implementation |
|----------|---------------|
| **No hardcoded credentials** | All passwords in `.env`, referenced via `${VAR}` in docker-compose.yml |
| **`.env` gitignored** | Listed in `.gitignore` — never accidentally committed |
| **`.env.example` committed** | Contains only placeholders, safe to share |
| **Mandatory password check** | `${GRAFANA_ADMIN_PASSWORD:?...}` syntax — compose refuses to start if unset |
| **No anonymous Grafana access** | `GF_AUTH_ANONYMOUS_ENABLED=false` |
| **No public registration** | `GF_USERS_ALLOW_SIGN_UP=false` |
| **Read-only config mounts** | All config files mounted with `:ro` |
| **Private Docker network** | All inter-service traffic stays on the `monitoring` bridge network |
| **SMTP optional** | Empty `SMTP_*` vars disable email — deployment never breaks without it |

### ⚠️ Secret Rotation Notice

This project was initialized **without a git repository**, so no credentials have ever been committed to git history. When you run `git init` and push to GitHub:

1. Confirm `.gitignore` is in place **before** `git add`
2. Run `git check-ignore -v .env` to verify it's excluded
3. Only then run `git add . && git commit`
4. Never run `git add .env` explicitly

---

## 📸 Screenshots Checklist

- [ ] `docker compose ps` — all 4 containers `healthy`
- [ ] `bash scripts/health_check.sh` — all green
- [ ] Grafana login page — http://localhost:3000
- [ ] Dashboard — **SentinelOps - System Overview** with all panels showing data
- [ ] Prometheus targets — http://localhost:9090/targets — all 4 UP
- [ ] Prometheus graph — run `up` query
- [ ] Prometheus alerts — http://localhost:9090/alerts — 12 rules loaded
- [ ] Alertmanager — http://localhost:9093
- [ ] `bash scripts/monitor.sh --once` — terminal stats
- [ ] `python3 scripts/validate_queries.py` — 27/27 PASS

---

## 🚀 Next Steps

### Beginner
- [ ] Configure email alerts (fill in `SMTP_*` vars in `.env`, update `alertmanager.yml`)
- [ ] Add Slack notifications (`SLACK_WEBHOOK_URL` in `.env`)
- [ ] Import the [Node Exporter Full](https://grafana.com/grafana/dashboards/1860) community dashboard (ID 1860)
- [ ] Initialise git: `git init && git add . && git commit -m "Initial SentinelOps setup"`

### Intermediate
- [ ] Add **cAdvisor** to monitor Docker container resource usage
- [ ] Add **Loki + Promtail** for log aggregation
- [ ] Add **Blackbox Exporter** to monitor external URLs
- [ ] Set up Grafana alerting (in addition to Alertmanager)

### Advanced
- [ ] Deploy to a cloud VM (AWS EC2, DigitalOcean Droplet, GCP)
- [ ] Add **Thanos** for long-term Prometheus storage
- [ ] Add **Kubernetes** monitoring with kube-state-metrics
- [ ] GitOps: store configs in Git, auto-apply on push

---

*Built as a complete DevOps learning project. All configurations validated against live services.*
