COMPOSE = docker compose

.PHONY: build down logs up verify

build:
	$(COMPOSE) build

up:
	$(COMPOSE) up --detach --wait

verify: up
	$(COMPOSE) exec --no-TTY database verify-pg-show-plans

logs:
	$(COMPOSE) logs

down:
	$(COMPOSE) down --volumes --remove-orphans
