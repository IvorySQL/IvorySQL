PYTHON ?= python3
COMPOSE ?= docker compose
HARNESS := $(PYTHON) migration_harness.py

.PHONY: build config preflight up verify report logs down clean test

build:
	$(COMPOSE) build

config:
	$(COMPOSE) config --quiet

preflight:
	@set -a; . ./.env; set +a; $(HARNESS) preflight --contract compatibility_contract.json

up:
	$(COMPOSE) up --detach --build --wait database

verify:
	$(COMPOSE) exec database /usr/local/bin/verify-orafce

report:
	$(COMPOSE) exec database cat /var/lib/ivorysql/reports/audit.json

logs:
	$(COMPOSE) logs --follow --tail 100 database

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down --volumes --remove-orphans

test:
	$(PYTHON) -m unittest discover -s tests -v
