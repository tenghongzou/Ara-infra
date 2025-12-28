# Ara Infrastructure Makefile
# ============================

.PHONY: help init up down restart build logs status clean test

.DEFAULT_GOAL := help

# ============================================================================
# Help
# ============================================================================

help:
	@echo ""
	@echo "Ara Infrastructure - Development Commands"
	@echo "=========================================="
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Initialization:"
	@echo "  init                 Initialize project (submodules + build + start)"
	@echo "  env-setup            Create .env from .env.example"
	@echo "  env-generate-secret  Generate a secure JWT secret"
	@echo ""
	@echo "Docker Services:"
	@echo "  up                   Start all services"
	@echo "  down                 Stop all services"
	@echo "  restart              Restart all services"
	@echo "  build                Build all services"
	@echo "  build-no-cache       Build without cache"
	@echo "  logs                 Show all logs"
	@echo "  logs-php             Show PHP logs"
	@echo "  logs-notification    Show Notification logs"
	@echo "  status               Show service status"
	@echo ""
	@echo "Shell Access:"
	@echo "  php-shell            Shell into PHP container"
	@echo "  node-shell           Shell into Node container"
	@echo "  notification-shell   Shell into Notification container"
	@echo ""
	@echo "Database:"
	@echo "  psql                 PostgreSQL CLI"
	@echo "  redis-cli            Redis CLI"
	@echo "  redis-monitor        Monitor Redis Pub/Sub"
	@echo "  db-migrate           Run migrations"
	@echo "  db-backup            Backup to backup.sql"
	@echo "  db-restore           Restore from backup.sql"
	@echo ""
	@echo "Testing:"
	@echo "  test                 Run all tests"
	@echo "  test-notification    Run Notification tests (265 tests)"
	@echo "  test-backend         Run Symfony tests"
	@echo "  test-admin           Run Admin tests"
	@echo ""
	@echo "Notification Service:"
	@echo "  notify-health        Health check"
	@echo "  notify-stats         Show statistics"
	@echo "  notify-test          Send test broadcast"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean                Remove containers"
	@echo "  clean-volumes        Remove containers + volumes"
	@echo "  clean-all            Remove everything"
	@echo ""

# ============================================================================
# Initialization
# ============================================================================

init: env-check
	@echo "Initializing Ara Infrastructure..."
	git submodule update --init --recursive
	docker-compose up -d --build
	@echo ""
	@echo "Done! Services are starting..."
	@echo ""
	@echo "Service URLs:"
	@echo "  Symfony API:    https://localhost"
	@echo "  Admin Panel:    http://localhost:3000"
	@echo "  Notification:   http://localhost:8081"
	@echo ""
	$(MAKE) status

env-check:
	@test -f .env || (echo "Error: .env not found! Run: make env-setup" && exit 1)

env-setup:
	@test -f .env && echo ".env already exists" || (cp .env.example .env && echo "Created .env - please edit JWT_SECRET")

env-generate-secret:
	@echo "Generated JWT Secret:"
	@openssl rand -base64 32 2>/dev/null || python -c "import secrets; print(secrets.token_urlsafe(32))"

# ============================================================================
# Docker Services
# ============================================================================

up: env-check
	docker-compose up -d
	@echo "Services started"

down:
	docker-compose down

restart:
	docker-compose restart

restart-php:
	docker-compose restart php

restart-notification:
	docker-compose restart notification

build:
	docker-compose build

build-notification:
	docker-compose build notification

build-no-cache:
	docker-compose build --no-cache

logs:
	docker-compose logs -f

logs-php:
	docker-compose logs -f php

logs-notification:
	docker-compose logs -f notification

logs-admin:
	docker-compose logs -f administration

status:
	docker-compose ps

# ============================================================================
# Shell Access
# ============================================================================

php-shell:
	docker-compose exec php bash

node-shell:
	docker-compose exec administration sh

notification-shell:
	docker-compose exec notification sh

# ============================================================================
# Database
# ============================================================================

psql:
	docker-compose exec postgres psql -U symfony -d symfony

redis-cli:
	docker-compose exec redis redis-cli

redis-monitor:
	@echo "Monitoring notification:* channels..."
	docker-compose exec redis redis-cli PSUBSCRIBE "notification:*"

db-migrate:
	docker-compose exec php bin/console doctrine:migrations:migrate --no-interaction

db-backup:
	docker-compose exec postgres pg_dump -U symfony symfony > backup.sql
	@echo "Backed up to backup.sql"

db-restore:
	docker-compose exec -T postgres psql -U symfony symfony < backup.sql
	@echo "Restored from backup.sql"

# ============================================================================
# Testing
# ============================================================================

test: test-notification

test-notification:
	@echo "Running Notification tests..."
	cd services/notification && cargo test

test-notification-verbose:
	cd services/notification && cargo test -- --nocapture

test-backend:
	docker-compose exec php bin/phpunit

test-admin:
	docker-compose exec administration pnpm test:unit

# ============================================================================
# Notification Service
# ============================================================================

notify-health:
	@curl -s http://localhost:8081/health | python -m json.tool 2>/dev/null || curl -s http://localhost:8081/health

notify-stats:
	@curl -s http://localhost:8081/stats | python -m json.tool 2>/dev/null || curl -s http://localhost:8081/stats

notify-metrics:
	@curl -s http://localhost:8081/metrics

notify-test:
	@echo "Sending test broadcast..."
	@curl -X POST http://localhost:8081/api/v1/notifications/broadcast \
		-H "Content-Type: application/json" \
		-d "{\"event_type\":\"test\",\"payload\":{\"message\":\"Hello from Makefile\"}}"
	@echo ""

# ============================================================================
# Cleanup
# ============================================================================

clean:
	docker-compose down --remove-orphans

clean-volumes:
	docker-compose down -v --remove-orphans

clean-all:
	docker-compose down -v --rmi all --remove-orphans

clean-notification-build:
	cd services/notification && cargo clean

# ============================================================================
# Shortcuts
# ============================================================================

dev: up logs

rebuild: down build up

rebuild-notification:
	docker-compose up -d --build notification
	docker-compose logs -f notification
