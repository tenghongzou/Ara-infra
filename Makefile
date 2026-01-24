# Ara Infrastructure - Makefile
# Docker Compose helper commands

# Use Docker Compose V2
COMPOSE = docker compose

.PHONY: help up down build logs status restart clean ps shell-php shell-node shell-notification

## Help
help: ## Show this help message
	@echo "Ara Infrastructure - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

## Docker Operations
up: ## Start all services
	$(COMPOSE) up -d
	@echo "Waiting for PHP container to be ready..."
	@sleep 3
	$(COMPOSE) exec -T php composer install --prefer-dist --no-interaction --quiet || true

down: ## Stop all services
	$(COMPOSE) down

build: ## Build all services
	$(COMPOSE) build

rebuild: ## Rebuild and restart all services
	$(COMPOSE) build && $(COMPOSE) up -d

restart: ## Restart all services
	$(COMPOSE) restart

status: ## Show service status
	$(COMPOSE) ps

logs: ## View all logs
	$(COMPOSE) logs -f

clean: ## Stop and remove all containers, volumes, and images
	$(COMPOSE) down -v --remove-orphans

ps: ## Show running containers
	$(COMPOSE) ps

## Service-Specific Shells
php-shell: ## Shell into PHP container
	$(COMPOSE) exec php bash

node-shell: ## Shell into Node/Administration container
	$(COMPOSE) exec administration sh

notification-shell: ## Shell into Notification container
	$(COMPOSE) exec notification sh

chat-shell: ## Shell into Chat container
	$(COMPOSE) exec chat sh

backup-shell: ## Shell into Backup container
	$(COMPOSE) exec backup bash

scheduler-shell: ## Shell into Scheduler container
	$(COMPOSE) exec scheduler bash

## Database Operations
psql: ## PostgreSQL CLI
	$(COMPOSE) exec postgres psql -U symfony -d symfony

redis-cli: ## Redis CLI
	$(COMPOSE) exec redis redis-cli

db-migrate: ## Run Symfony migrations
	$(COMPOSE) exec php bin/console doctrine:migrations:migrate --no-interaction

## Scheduler Operations
scheduler-status: ## Show registered schedules and next run times
	$(COMPOSE) exec php bin/console debug:scheduler

scheduler-restart: ## Restart the scheduler worker
	$(COMPOSE) restart scheduler

scheduler-run: ## Run scheduled tasks immediately (for testing)
	$(COMPOSE) exec php bin/console messenger:consume scheduler_main --limit=1 -vv

## Testing
test-backend: ## Run Symfony tests
	$(COMPOSE) exec php bin/phpunit

test-admin: ## Run SvelteKit tests
	$(COMPOSE) exec administration pnpm test:unit

test-notification: ## Run Rust notification tests
	cd services/notification && cargo test

test-chat: ## Run Rust chat tests
	cd services/chat && cargo test

## Backup Operations
backup-now: ## Run immediate backup
	$(COMPOSE) exec backup /scripts/backup.sh all

backup-restore: ## Restore from latest backup
	$(COMPOSE) exec backup /scripts/restore.sh

backup-logs: ## View backup logs
	$(COMPOSE) exec backup tail -f /var/log/backup/backup.log

## Service Logs
logs-php: ## View PHP logs
	$(COMPOSE) logs -f php

logs-admin: ## View Administration logs
	$(COMPOSE) logs -f administration

logs-notification: ## View Notification logs
	$(COMPOSE) logs -f notification

logs-chat: ## View Chat logs
	$(COMPOSE) logs -f chat

logs-postgres: ## View PostgreSQL logs
	$(COMPOSE) logs -f postgres

logs-backup: ## View Backup logs
	$(COMPOSE) logs -f backup

logs-scheduler: ## View Scheduler logs
	$(COMPOSE) logs -f scheduler

## Health Checks
health: ## Check health of all services
	@echo "Checking service health..."
	@echo "PHP Backend:"
	@curl -s http://localhost/api/health || echo "  [X] Not responding"
	@echo "\nAdministration:"
	@curl -s http://localhost:3000 > /dev/null && echo "  [OK] Running" || echo "  [X] Not responding"
	@echo "\nNotification:"
	@curl -s http://localhost:8081/health || echo "  [X] Not responding"
	@echo "\nChat:"
	@curl -s http://localhost:8082/health || echo "  [X] Not responding"
	@echo "\nScheduler:"
	@$(COMPOSE) exec -T scheduler php bin/console debug:scheduler --date=now > /dev/null 2>&1 && echo "  [OK] Running" || echo "  [X] Not responding"
