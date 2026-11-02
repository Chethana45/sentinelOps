# =============================================================================
# SentinelOps - Makefile
# =============================================================================
# Shortcut commands for common operations.
# Usage:  make <target>
# Run  :  make help   to list all available targets.
# =============================================================================

.DEFAULT_GOAL := help
.PHONY: help up down restart logs logs-prometheus logs-grafana \
        logs-alertmanager logs-node-exporter ps health monitor \
        pull validate clean reset setup reload-prometheus

CYAN  := \033[0;36m
BOLD  := \033[1m
RESET := \033[0m

## ─── Stack Control ──────────────────────────────────────────────────────────

## up: Start all monitoring services in the background
up:
	@echo "$(CYAN)Starting SentinelOps stack...$(RESET)"
	docker compose up -d
	@echo "$(CYAN)Done. Grafana -> http://localhost:3000$(RESET)"

## down: Stop all services (data volumes are preserved)
down:
	@echo "$(CYAN)Stopping SentinelOps stack...$(RESET)"
	docker compose down
	@echo "$(CYAN)Services stopped.$(RESET)"

## restart: Restart all services
restart:
	docker compose restart

## pull: Pull the latest Docker images
pull:
	docker compose pull

## ─── Observability ──────────────────────────────────────────────────────────

## ps: Show container status
ps:
	docker compose ps

## logs: Follow logs from ALL services (Ctrl+C to stop)
logs:
	docker compose logs -f

## logs-prometheus: Follow Prometheus logs only
logs-prometheus:
	docker compose logs -f prometheus

## logs-grafana: Follow Grafana logs only
logs-grafana:
	docker compose logs -f grafana

## logs-alertmanager: Follow Alertmanager logs only
logs-alertmanager:
	docker compose logs -f alertmanager

## logs-node-exporter: Follow Node Exporter logs only
logs-node-exporter:
	docker compose logs -f node-exporter

## ─── Scripts ────────────────────────────────────────────────────────────────

## health: Run the service health check script
health:
	@bash scripts/health_check.sh

## monitor: Launch the terminal system monitor (Ctrl+C to exit)
monitor:
	@bash scripts/monitor.sh

## setup: Run the full guided setup script
setup:
	@bash scripts/setup.sh

## ─── Config Management ──────────────────────────────────────────────────────

## validate: Validate docker-compose.yml syntax
validate:
	@echo "$(CYAN)Validating docker-compose.yml...$(RESET)"
	@docker compose config --quiet && echo "docker-compose.yml: OK"

## reload-prometheus: Hot-reload Prometheus config (no container restart)
reload-prometheus:
	@echo "$(CYAN)Reloading Prometheus configuration...$(RESET)"
	curl -s -X POST http://localhost:9090/-/reload
	@echo "$(CYAN)Prometheus config reloaded!$(RESET)"

## ─── Cleanup ─────────────────────────────────────────────────────────────────

## clean: Remove stopped containers and dangling images
clean:
	docker compose down --remove-orphans
	docker image prune -f

## reset: DANGER - Remove containers AND all data volumes (metrics history lost)
reset:
	@echo "WARNING: Deletes ALL metrics data, dashboard saves, and alert state."
	@read -p "Type 'yes' to confirm: " c; \
	  [ "$$c" = "yes" ] \
	  && docker compose down --volumes --remove-orphans \
	  && echo "Reset complete." \
	  || echo "Cancelled."

## ─── Help ────────────────────────────────────────────────────────────────────

## help: Show this help message
help:
	@echo ""
	@echo "$(BOLD)SentinelOps - Available Make Targets$(RESET)"
	@echo "$(CYAN)─────────────────────────────────────────$(RESET)"
	@grep -E '^## ' $(MAKEFILE_LIST) \
	  | sed 's/^## //' \
	  | column -t -s ':'
	@echo ""
